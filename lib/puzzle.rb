require 'scanf'

module Puzrb
  # Encapsulates a puzzle.
  # Provides ability to load (and verify) and write.
  # Provides full editing and checking of puzzle.
  class Puzzle
    include Checksum

    attr_reader :raw
    attr_reader :start_junk

    attr_reader :board_checksum
    attr_reader :file_magic

    attr_reader :cib_checksum
    attr_reader :masked_low_checksums
    attr_reader :masked_high_checksums

    attr_reader :version
    attr_reader :reserved_1c
    attr_reader :scrambled_checksum
    attr_reader :reserved_20

    attr_reader :width
    attr_reader :height
    attr_reader :n_clues

    attr_reader :bitmask # unknown as to what this is, usually 1
    attr_reader :scrambled_tag

    attr_reader :solution_pos
    attr_reader :solution
    attr_reader :state

    attr_reader :description
    attr_reader :title
    attr_reader :author
    attr_reader :copyright
    attr_reader :clues
    attr_reader :notes

    attr_reader :extras # hash keyed on extra cmd (GRBD|RTBL|LTIM|GEXT|RUSR)

    attr_reader :clue_map, :across_clues, :down_clues

    attr_reader :design_mode

    # See #method_missing for how COLORS are used to colorify output with ghost methods.
    COLORS = %w(black red green yellow blue magenta cyan white)

    def initialize
    end

    # Load, verify and set up puzzle state.
    def self.load io
      p = Puzzle.new
      p._load io
      p.verify
      p.map_clues
      p
    end

    # Read in a .puz file
    # This does not verify the integrity of the data with respect to checksums.
    # see #verify
    def _load io
      # We're not setting solution letters or clues (but this could be set subsequently)
      @design_mode = false

      @raw = io.read
      io.rewind

      file_magic_idx = @raw.index "ACROSS&DOWN"
      raise "This doesn't look like a .puz file" if file_magic_idx.nil?
      @start_junk = io.read(file_magic_idx - 2) # if we have junk at the start

      # header
      @board_checksum = io.read(2).unpack('v')[0]
      @file_magic = io.read(12).unpack('Z*')[0]

      @cib_checksum = io.read(2).unpack('v')[0]
      @masked_low_checksums = io.read(4).unpack('H*')[0]
      @masked_high_checksums = io.read(4).unpack('H*')[0]

      @version = io.read(4).unpack('Z*')[0]
      @reserved_1c = io.read(2)
      @scrambled_checksum = io.read(2).unpack('v')[0]
      @reserved_20 = io.read(12)

      @width = io.read(1).unpack('C')[0]
      @height = io.read(1).unpack('C')[0]
      @n_clues = io.read(2).unpack('v')[0]

      @bitmask = io.read(2).unpack('v')[0]
      @scrambled_tag = io.read(2).unpack('v')[0]

      # solution: . is black square
      @solution = io.read(@width * @height)
      @state = io.read(@width * @height)

      @title = read_string io
      @author = read_string io
      @copyright = read_string io
      @clues = @n_clues.times.map { read_string io }
      @notes = read_string io

      # slurp in all extra sections, key on section name
      @extras = {}
      while (name = io.read(4))
        extra = Puzrb.const_get(name).new self
        extra.length = io.read(2).unpack('v')[0]
        extra.checksum = io.read(2).unpack('v')[0]
        extra.data = io.read(extra.length + 1)
        @extras[name] = extra
      end

      # To solve we need a GEXT to set bit masks if squares are indicated as incorrect etc.
      # If we didn't have it in the file then create it.
      # TODO: probably only have this if puzzle is edited and any masks are set.
      #       this will ensure bindary compatability with reading then writing, and
      #       match what AcrossLite does.
      if gext.nil?
#        puts "WARNING: no GEXT in puzzle, creating blank"
        @extras['GEXT'] = g = GEXT.new(self)
        g.blank!
        # force a serialize so that it passes verification by setting length and checksum
        g.serialize
      end

      self
    end

    # Read in a NUL terminated string from io.
    def read_string io
      buf = ''
      while (c = io.read(1)) != "\0"
        buf += c
      end
      buf
    end

    def calculate_checksum cs_sym
      case cs_sym
      when :cib_checksum
        chksum [@width,@height,@n_clues,@bitmask,@scrambled_tag].pack('CCvvv')
      when :board_checksum
        cs = chksum @solution, calculate_checksum(:cib_checksum)
        cs = chksum @state, cs
        [:@title, :@author, :@copyright].each do |a|
          v = instance_variable_get a
          cs = chksum("#{v}\0", cs) unless v.nil? || v.empty?
        end
        cs = @clues.reduce(cs) { |p,c| chksum c, p }
        cs = chksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
        cs
      when :masked_checksums_base
        # doesn't correspond to an instance variable, but is used for the other masked checksums
        cs = 0x0
        [:@title, :@author, :@copyright].each do |a|
          v = instance_variable_get a
          cs = chksum("#{v}\0", cs) unless v.nil? || v.empty?
        end
        cs = @clues.reduce(cs) { |p,c| chksum c, p }
        cs = chksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
        cs
      when :masked_low_checksums
        cs = calculate_checksum :masked_checksums_base
        [0x49 ^ (calculate_checksum(:cib_checksum) & 0xff),
         0x43 ^ (chksum(@solution) & 0xff),
         0x48 ^ (chksum(@state) & 0xff),
         0x45 ^ (cs & 0xff)].pack('C*').unpack('H*')[0]
      when :masked_high_checksums
        cs = calculate_checksum :masked_checksums_base
        [0x41 ^ ((calculate_checksum(:cib_checksum) & 0xff00) >> 8),
         0x54 ^ ((chksum(@solution) & 0xff00) >> 8),
         0x45 ^ ((chksum(@state) & 0xff00) >> 8),
         0x44 ^ ((cs & 0xff00) >> 8)].pack('C*').unpack('H*')[0]
      else
        raise "Don't know about checksum type:#{cs_sym}"
      end
    end

    # calculate_checksum, but will raise an error, and print if correct
    def verify_checksum cs
      checksum = calculate_checksum cs
      orig = instance_variable_get "@#{cs.to_s}".to_sym
      raise "Bad #{cs.id2name} checksum:#{checksum} vs orig:#{orig}" unless checksum == orig
      checksum
    end

    # Check integrity of puzzle (lengths, checksums, cross-referenced elements).
    def verify
      puts "NOTE: puzzle is scrambled" if is_scrambled?

      # n clues
      raise "Wrong number of clues:#{@clues.length} expected:#{@n_clues}" unless @clues.length == @n_clues

      verify_checksum :cib_checksum
      verify_checksum :board_checksum
      verify_checksum :masked_low_checksums
      verify_checksum :masked_high_checksums

      # Extras
      @extras.each_pair { |name,e| e.verify }

      if grbs.nil?
        # No warning needed here
      elsif rtbl.nil?
        puts "WARNING: have GRBS but no RTBL"
      else
        # Check any rebuses referenced in GRBS match with RTBL
        sol_rebuses = [] # to see if there are any defined which aren't referenced in the solution
        (0...@height).each do |r|
          (0...@width).each do |c|
            r_n = grbs.rebus_n_at r, c
            if r_n > 0
              if (reb = rtbl.rebus_for_n(r_n)) == nil
                raise "Rebus n:#{r_n} has no matching definition"
              else
                sol_rebuses << r_n
              end
            end
          end
        end
        reb_unused = rtbl.rebuses.reject! { |r| sol_rebuses.include? r[:n] }
        if ! reb_unused.empty?
          puts "WARNING: the following rebuses are defined but not referenced in the solution:",
          reb_unused.inspect
        end
      end
    end

    # 1. Map each cell to:
    #  - across clue
    #  - down clue
    #  - whether it starts an across or down answer
    # 2. Builds ordered lists of across and down clues, and their global clue number.
    def map_clues
      @clue_map = {} # state_idx => { :across => n (across_clues index), :across_start => t (or missing),
      #                               :down   => n (down_clues index)  , :down_start   => t (or missing) }
      @across_clues = [] # [@clues index, global clue #]
      @down_clues = []   # [@clues index, global clue #]
      clue_idx = -1
      global_clue_n = 0
      (0...@height).each do |r|
        (0...@width).each do |c|
          if is_black? r,c
          else
            val = {}
            # across
            if c > 0 && !is_black?(r, c-1) # have white to left, inherit clue
              val[:across] = @clue_map[rc2idx(r, c) - 1][:across]
            elsif c < @width - 1 && !is_black?(r, c + 1) # have white to right, start of across
              val[:across] = @across_clues.length
              val[:is_across_start] = true
              @across_clues << [clue_idx += 1,global_clue_n += 1]
            end
            # down
            if r > 0 && !is_black?(r-1, c) # have white above, inherit clue
              val[:down] = @clue_map[rc2idx(r -1 , c)][:down]
            elsif r < @height - 1 && !is_black?(r + 1, c) # have white below, start of down
              val[:down] = @down_clues.length
              val[:is_down_start] = true
              # Increment global clue iff we didn't start an across clue
              @down_clues << [clue_idx += 1, val[:is_across_start] ? global_clue_n : global_clue_n += 1]
            end
            @clue_map[rc2idx(r, c)] = val
          end
        end
      end
    end

    # row,col -> index
    def rc2idx r, c
      r * @width + c
    end

    # index -> row,col
    def idx2rc idx
      [idx / @width, idx % @width]
    end

    # Is the puzzle scrambled?
    def is_scrambled?
      @scrambled_checksum > 0
    end

    # Is row,col a black square in the grid definition?
    def is_black? r, c
      solution_letter_at(r,c) == '.'
    end

    # Get letter from solution
    # Note that if the puzzle is scrambled this will simply return the scrambled letter,
    # not the true solution letter.
    def solution_letter_at r, c
      @solution[rc2idx(r, c)]
    end

    # Get letter from current state
    def letter_at r, c
      @state[rc2idx(r, c)]
    end

    # Get solution word that the given square is part of, with respect to the given direction.
    # Note that if the puzzle is scrambled this will simply return the scrambled word,
    # not the true solution word.
    def solution_word_at r, c, dir
      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue r,c is for
      letter = @clue_map[r * @width + c]
      # get all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.map { |i,c|
        r, c = idx2rc i
        solution_letter_at r, c
      }.join
    end

    # Get word that the given square is part of, with respect to the given direction.
    def word_at r, c, dir
      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue r,c is for
      letter = @clue_map[r * @width + c]
      # get all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.map { |i,c|
        r, c = idx2rc i
        letter_at r, c
      }.join
    end

    # Set letter in current state.
    def set_letter_at r, c, l
      l = l[0].upcase
      if (65..90).include? l.ord
        @state[rc2idx(r, c)] = l
        if gext.mask? r, c, GEXT::CURR_INCORRECT
          gext.set_mask r, c, GEXT::PREV_INCORRECT
        end
      end
    end

    # Set rebus string 's' at row,col.
    def set_rebus_at r, c, s
      # TODO
    end

    # Whether the given row,col is a letter (rather than outside the grid or a black square).
    def is_letter? r, c
      ! (is_black?(r, c) || r < 0 || r >= @height || c < 0 || c >= @width)
    end

    # Check entered letter at row,col and set corresponding flag in GEXT if applicable.
    # Returns true if state letter matches solution, false otherwise.
    #
    # If the puzzle is scrambled, this returns nil, and no flags are set.
    # A single letter can't be checked against the true scrambled solution.
    def check_letter r, c
      return nil if is_scrambled?

      if ! is_letter? r, c
        raise "Bad row:#{r},col:#{c}"
      end
      if letter_at(r, c) != solution_letter_at(r, c)
        gext.set_mask r, c, GEXT::CURR_INCORRECT
        false
      else
        true
      end
    end

    # Check whole word that spans letter at row,col for direction dir (:accross|:down), and
    # sets corresponding flags in GEXT if applicable.
    # Returns true if state word matches solution, false otherwise.
    #
    # If the puzzle is scrambled, this returns nil, and no flags are set.
    # A single letter (and therefore words) can't be checked against the true scrambled solution.
    def check_word r, c, dir
      return nil if is_scrambled?

      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue mapping r,c is for
      letter = @clue_map[rc2idx(r, c)]
      # check all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.all? { |i,c|
        r, c = idx2rc i
        check_letter r, c
      }
    end

    # Check entire grid and set corresponding flags in GEXT if applicable.
    #
    # If the puzzle is scrambled, this returns true or false, but no GEXT flags are set
    # either way.
    def check_all
      if is_scrambled?
        # Match scrambled_checksum with user grid
        puts "scrambled_checksum:#{@scrambled_checksum} chksum:#{chksum @state}"
        @scrambled_checksum == chksum(@state)
      else
        (0...@height).map do |r|
          (0...@width).map do |c|
            is_letter?(r,c) ? check_letter(r,c) : nil
          end
        end.flatten.compact.all? { |e| !!e } # if we have all 'true' squares then solution is correct
      end
    end

    def reveal_letter r, c
      return nil if is_scrambled?

      if ! is_letter? r, c
        raise "Bad row:#{r},col:#{c}"
      end
      sol_l = solution_letter_at(r, c)
      if letter_at(r, c) != sol_l
        @state[rc2idx(r, c)] = sol_l
        gext.set_mask r, c, GEXT::REVEALED
      end
    end

    def reveal_word r, c, dir
      return nil if is_scrambled?

      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue mapping r,c is for
      letter = @clue_map[rc2idx(r, c)]
      # check all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.each { |i,c|
        r, c = idx2rc i
        reveal_letter r, c
      }
    end

    def reveal_all
      return nil if is_scrambled?

      (0...@height).each do |r|
        (0...@width).each do |c|
          if is_letter? r, c
            reveal_letter r, c
          end
        end
      end
    end

    # Scrambled current state with the given 4-digit key.
    def scramble key
      # solution is the completed grid column-wise rather than the normal row-wise, with
      # black squares removed.
      sol = (0...@width).map do |c|
        (0...@height).map do |r|
          is_black?(r, c) ? nil : letter_at(r, c)
        end.compact
      end.join

      sol = key.to_s.split('').reduce(sol) do |cur_sol,k|
        cur_sol = cur_sol.to_s.map.with_index do |s,i|
          l = s.ord + key[i % 4]
          l > 90 ? l - 26 : l
        end
        cur_sol.rotate! k
        mid = cur_sol.length / 2
        cur_sol[mid..-1].split('').zip(cur_sol[0,mid].split('')).join
      end
    end

    # convenience method for GRBS extra
    def grbs
      @extras['GRBS']
    end

    # convenience method for RTBL extra
    def rtbl
      @extras['RTBL']
    end

    # convenience method for LTIM extra
    def ltim
      @extras['LTIM']
    end

    # convenience method for GEXT extra
    def gext
      @extras['GEXT']
    end

    # convenience method for RUSR extra
    def rusr
      @extras['RUSR']
    end

    def print_solution
      puts @solution.scan(/.{#{@width}}/)
    end

    def print_state
      puts @state.scan(/.{#{@width}}/)
    end

    # Print state with colors corresponding to state flags.
    def print_state_ext
      (0...@height).each do |r|
        (0...@width).each do |c|
          if is_black? r, c
            print ' '
          else
            l = letter_at r, c
            if gext.mask? r, c, GEXT::PREV_INCORRECT
              print_magenta l
            elsif gext.mask? r, c, GEXT::CURR_INCORRECT
              print_red l
            else
              print l
            end
          end
        end
        puts "\n"
      end
    end

    def zstring s
      "#{s}\0"
    end

    def write file
      open(file, 'w') { |o| o.write serialize }
    end

    # Binary form of puzzle
    def serialize io
      to_write = [@start_junk,
                  [@board_checksum, @file_magic, @cib_checksum].pack('vZ12v'),
                  [@masked_low_checksums, @masked_high_checksums].pack('H8H8'),
                  [@version, @reserved_1c, @scrambled_checksum, @reserved_20].pack('Z4Z2vZ12'),
                  [@width, @height, @n_clues, @bitmask, @scrambled_tag].pack('CCvvv'),
                  @solution,
                  @state,
                  [@title, @author, @copyright].map { |s| zstring(s) }.join,
                  @clues.map { |s| zstring(s) }.join,
                  zstring(@notes)] # TODO: only do this for >=v1.3

      %w(GRBS RTBL LTIM GEXT RUSR).each do |e|
        if ex = @extras[e]
          to_write << ex.serialize
        end
      end

      to_write.each { |data| io.write data }

      # We'll leave encodings as is, and not do the conversions below.
      # Some crossword sources use UTF-8 and we'll let other things (i.e. AcrossLite)
      # deal with it.
      #
      #      to_write.each { |data| data.force_encoding('ISO-8859-1') }
      #      to_write.join
    end

    # Provides convenience ghost methods for color printing.
    def method_missing sym, args
      if sym.id2name =~ /^print_([a-z]+)$/
        color = (COLORS.index($1) || 7) + 30 # defaults to white
        print "\u001B[#{color}m#{args}\u001B[m"
      else
        super
      end
    end

    # +++++ following methods are related to starting a new puzzle from scratch
    #       rather than loading one from a file

    # Start a new, empty, editable puzzle.
    # Editable means the solution grid and clues can be set.
    # width and height are required.
    def self.new_blank width, height
      puzzle = Puzzle.new

      # instance_eval here is very helpful as we don't have to keep referring
      # to puzzle to set state.
      puzzle.instance_eval do
        @design_mode = true

        @start_junk = ''

        @board_checksum = 0
        @file_magic = "ACROSS&DOWN\0"

        @cib_checksum = 0
        @masked_low_checksums = 0
        @masked_high_checksums = 0

        @version = "1.3"
        @reserved_1c = ''
        @scrambled_checksum = 0
        @reserved_20 = ''

        @width = width
        @height = height
        @n_clues = 0

        @bitmask = 1
        @scrambled_tag = 0

        @solution = '.' * @width * @height
        @state = '.' * @width * @height

        @title = ''
        @author = ''
        @copyright = ''
        @clues = []
        @notes = ''

        @extras = {}

        @extras['GEXT'] = g = GEXT.new(self)
        g.blank!
        g.serialize
      end

      puzzle
    end

    def set_solution_letter row, col, letter #, clue_number
      @solution[rc2idx(row, col)] = letter
    end

  end

end
