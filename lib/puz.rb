require 'scanf'

module Puzrb
  module Checksum
    def chksum data, cksum=0
      data.each_byte.reduce(cksum) do |p,c|
        (c + ((p & 0x1 == 0) ? (p >> 1) : (p >> 1 | 0x8000))) & 0xffff
      end
    end
  end

  class Puzzle
    include Checksum

    attr_accessor :raw
    attr_accessor :start_junk

    attr_accessor :checksum # overall checksum
    attr_accessor :file_magic

    attr_accessor :cib_checksum
    attr_accessor :masked_low_checksums
    attr_accessor :masked_high_checksums

    attr_accessor :version
    attr_accessor :reserved_1c
    attr_accessor :scrambled_checksum
    attr_accessor :reserved_20

    attr_accessor :width
    attr_accessor :height
    attr_accessor :n_clues

    attr_accessor :bitmask
    attr_accessor :scrambled_tag

    attr_accessor :solution_pos
    attr_accessor :solution
    attr_accessor :state

    attr_accessor :description
    attr_accessor :title
    attr_accessor :author
    attr_accessor :copyright
    attr_accessor :clues
    attr_accessor :notes

    attr_accessor :extras # hash keyed on extra cmd (GRBD|RTBL|LTIM|GEXT|RUSR)

    def initialize
    end

    def self.load io
      p = Puzzle.new
      p._load io
      p.verify
      p.map_clues
      p
    end

    # Read in a .puz file
    # This does not validate the integrity of the data with respect to checksums.
    # see #verify
    def _load io
      @raw = io.read #.unpack('v*')
      io.rewind

      file_magic_idx = @raw.index "ACROSS&DOWN"
      raise "This doesn't look like a .puz file" if file_magic_idx.nil?
      @start_junk = io.read(file_magic_idx - 2) # if we have junk at the start

      # header
      @checksum = io.read(2).unpack('v')[0]
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
      @solution_pos = io.pos
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
    end

    def read_string io
      buf = ''
      while (c = io.read(1)) != "\0"
        buf += c
      end
      buf
    end

    def verify
      # n clues
      raise "Wrong number of clues:#{@clues.length} expected:#{@n_clues}" unless @clues.length == @n_clues

      # CIB checksum
      cib_cs = cs = chksum [@width,@height,@n_clues,@bitmask,@scrambled_tag].pack('CCvvv')
      raise "Bad CIB checksum:#{cs} vs orig:#{@cib_checksum}" unless cs == @cib_checksum
      puts "CIB checksum is good:#{cs}"

      # Primary board checksum
      cs = chksum @solution, cs
      cs = chksum @state, cs
      [:@title, :@author, :@copyright].each do |a|
        v = instance_variable_get a
        cs = chksum("#{v}\0", cs) unless v.nil? || v.empty?
      end
      cs = @clues.reduce(cs) { |p,c| chksum c, p }
      cs = chksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
      raise "Bad checksum:#{cs} vs orig:#{@checksum}" unless cs == @checksum
      puts "Checksum is good:#{cs}"

      # Masked checksums
      sol_cs = chksum @solution
      grd_cs = chksum @state
      cs = 0x0
      [:@title, :@author, :@copyright].each do |a|
        v = instance_variable_get a
        cs = chksum("#{v}\0", cs) unless v.nil? || v.empty?
      end
      cs = @clues.reduce(cs) { |p,c| chksum c, p }
      cs = chksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
      low = [0x49 ^ (cib_cs & 0xff),
             0x43 ^ (sol_cs & 0xff),
             0x48 ^ (grd_cs & 0xff),
             0x45 ^ (cs & 0xff)].pack('C*').unpack('H*')[0]
      raise "Bad masked low checksums:#{low} vs orig:#{@masked_low_checksums}" unless
        low == @masked_low_checksums
      puts "Masked low checksum is good:#{low}"
      hi = [0x41 ^ ((cib_cs & 0xff00) >> 8),
            0x54 ^ ((sol_cs & 0xff00) >> 8),
            0x45 ^ ((grd_cs & 0xff00) >> 8),
            0x44 ^ ((cs & 0xff00) >> 8)].pack('C*').unpack('H*')[0]
      raise "Bad masked high checksums:#{hi} vs orig:#{@masked_high_checksums}" unless
        hi == @masked_high_checksums
      puts "Masked high checksum is good:#{hi}"

      # Extras
      @extras.each_pair { |name,e| e.validate }

      # Check any rebuses referenced in GRBS match with RTBL
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
            elsif c < @width - 1 && !is_black?(r, c+1) # have white to right, start of across
              val[:across] = @across_clues.length
              val[:is_across_start] = true
              @across_clues << [clue_idx += 1,global_clue_n += 1]
            end
            # down
            if r > 0 && !is_black?(r-1, c) # have white above, inherit clue
              val[:down] = @clue_map[rc2idx(r -1 , c)][:down]
            elsif r < @height - 1 && !is_black?(r+1, c) # have white below, start of down
              val[:down] = @down_clues.length
              val[:is_down_start] = true
              # Increment global clue # only if we didn't start an across clue
              @down_clues << [clue_idx += 1, val[:is_across_start] ? global_clue_n : global_clue_n += 1]
            end
            @clue_map[rc2idx(r, c)] = val
          end
        end
      end
    end

    def rc2idx r, c
      r * @width + c
    end

    def idx2rc idx
      [idx / @width, idx % @width]
    end

    def is_black? r, c
      solution_letter_at(r,c) == '.'
    end

    # Get letter from solution
    def solution_letter_at r, c
      @solution[rc2idx(r, c)]
    end

    # Get letter from current state
    def letter_at r, c
      @state[rc2idx(r, c)]
    end

    # TODO: handle symbols and rebuses
    def set_letter_at r, c, l
      l = l[0].upcase
      if (65..90).include? l.ord
        @state[rc2idx(r, c)] = l
        if gext.mask? r, c, GEXT::CURR_INCORRECT
          gext.set_mask r, c, GEXT::PREV_INCORRECT
        end
      end
    end

    def is_letter? r, c
      ! (is_black?(r, c) || r < 0 || r >= @height || c < 0 || c >= @width)
    end

    # Check entered letter at row,col and set corresponding flag in GEXT extra if applicable.
    # Returns true if state letter matches solution, false otherwise.
    def check_letter r, c
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
    # set corresponding flags in GEXT extra if applicable.
    # Returns true if state word matches solution, false otherwise.
    def check_word r, c, dir
      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue mapping r,c is for
      letter = @clue_map[rc2idx(r, c)]
      # check all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.all? { |i,c|
        r, c = idx2rc i
        check_letter r, c
      }
    end

    # Check entire grid and set corresponding flags in GEXT extra if applicable.
    # TODO: return true|false
    def check_all
      (0..@height).each do |r|
        (0..@width).each do |c|
          check_letter r, c
        end
      end
    end

    # Get word that the given square is part of, with respect to the given direction.
    def get_word r, c, dir
      raise "Bad direction:#{dir.inspect}" unless [:across, :down].include?(dir)
      # get which clue r,c is for
      letter = @clue_map[r * @width + c]
      # get all squares which are the same word for the given direction
      @clue_map.select { |i,c| c[dir] == letter[dir] }.map { |i,c|
        r, c = idx2rc i
        letter_at r, c
      }
    end

    def grbs
      @extras['GRBS']
    end

    def rtbl
      @extras['RTBL']
    end

    def ltim
      @extras['LTIM']
    end

    def gext
      @extras['GEXT']
    end

    def rusr
      @extras['RUSR']
    end

    def print_solution
      puts @solution.scan(/.{#{@width}}/)
    end

    def print_state
      puts @state.scan(/.{#{@width}}/)
    end

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

    def method_missing sym, args
      if sym.id2name =~ /^print_([a-z]+)$/
        color = case $1
                when 'red'
                  '31'
                when 'green'
                  '32'
                when 'yellow'
                  '33'
                when 'magenta'
                  '35'
                else
                  '37'
                end
        print "\u001B[#{color}m#{args}\u001B[m"
      else
        super
      end
    end
  end

  class PuzExtra
    include Checksum

    attr_accessor :name
    attr_accessor :length
    attr_accessor :checksum
    attr_accessor :data

    def initialize puz
      @puz = puz
    end

    # Override to treat data in a specific way, but call super
    def data= data
      @data = data
    end

    def name
      self.class.name.split('::')[-1]
    end

    def validate
      raise "Bad length for extra:#{name}, length:#{data.length} expected:#{length}" unless
        data.length == length + 1
      puts "Extra:#{name} length is good:#{length}"
      cs = chksum data[0..-2] # data was read with \0, so strip for checksum
      raise "Bad extra:#{name} checksum:#{cs} expected:#{checksum}" unless
        cs == checksum
      puts "Extra:#{name} checksum is good:#{cs}"
    end

    # Return 'data'.
    # Subclasses must keep their 'data' up to date when their state is changed.
    def serialize
      puts "#{checksum} -> #{chksum(data[0..-2])}"
      name + [length, chksum(data[0..-2])].pack('vv') + data
    end
  end

  class GRBS < PuzExtra
    def data= data
      super
      @board = data.unpack 'C*'
    end

    def is_rebus? r, c
      rebus_at(r, c) != 0
    end

    # Get rebus number for position.
    # Note that if there is a rebus number at the given position it is decremented before
    # returning so that it matches RTBL number.
    def rebus_n_at r, c
      # raise?
      return 0 unless @puz.is_letter? r, c
      r = @board[r * @puz.width + c]
      r > 0 ? r - 1 : r
    end

    def print_board
      puts @board.map { |s| s.to_s(16).rjust(2, '0') }.join.scan(/.{#{@puz.width * 2}}/)
    end

    def set_rebus_n r, c, rebus_n
      @board[r * @puz.width + c] = rebus_n + 1
      @data = @board.pack('C*') + '\0'
      @length = @data.length
    end
  end

  class RTBL < PuzExtra
    def data= data
      super
      @rebuses = data.rstrip.split(';').map do |r|
        k,v = r.split ':'
        { :n => k.to_i, :val => v }
      end
    end

    def rebus_for_n n
      @rebuses.find { |r| r[:n] == n }
    end

    def set_rebus_for_n n, val
      current = rebus_for_n n
      if current
        current[:val] = val
      else
        @rebuses << {:n => n, :val => val}
      end
      @data = @rebuses.map { |r| "#{r[:n].to_s.rjust(2, '0')}:#{r[:val]};" }.pack('C*')
    end
  end

  class LTIM < PuzExtra
    attr_accessor :time_elapsed

    def data= data
      super
      @time_elapsed, @stopped = data.scanf '%d,%d'
    end

    def set_time_elapsed secs
      @time_elapsed = secs
      update
    end

    # Note that this just sets the state, it is up to some external object to maintain a timer.
    def start
      @stopped = 0
      update
    end

    # Note that this just sets the state, it is up to some external object to maintain a timer.
    def stop
      @stopped = 1
      update
    end

    private

    def update
      @data = "#{@time_elapsed},#{@stopped}"
    end
  end

  class GEXT < PuzExtra
    PREV_INCORRECT = 0x10 # square was previously marked incorrect
    CURR_INCORRECT = 0x20 # square is currently marked incorrect
    REVEALED       = 0x40 # contents of square were given
    CIRCLED        = 0x80 # square is circled. 

    def data= data
      super
      @states = data.unpack 'C*'
    end

    def check_mask mask
      raise "Bad mask:#{mask}" unless [PREV_INCORRECT, CURR_INCORRECT, REVEALED, CIRCLED].include?(mask)
    end

    def set_mask r, c, mask
      check_mask mask
      idx = @puz.rc2idx(r, c)
      @states[idx] |= mask
      # TODO: prevent going to PREV_INCORRECT or CURR_INCORRECT if currently have REVEALED set?
      #       AcrossLite prevents this in the UI.
      if mask == PREV_INCORRECT
        @states[idx] ^= CURR_INCORRECT if @states[idx] & CURR_INCORRECT > 0
        @states[idx] ^= REVEALED if @states[idx] & REVEALED > 0
      elsif mask == CURR_INCORRECT
        @states[idx] ^= PREV_INCORRECT if @states[idx] & PREV_INCORRECT > 0
        @states[idx] ^= REVEALED if @states[idx] & REVEALED > 0
      elsif mask == REVEALED
        @states[idx] ^= PREV_INCORRECT if @states[idx] & PREV_INCORRECT > 0
        @states[idx] ^= CURR_INCORRECT if @states[idx] & CURR_INCORRECT > 0
      end
      @data = @states.pack('C*')
    end

    def mask r, c
      @states[r * @puz.width + c]
    end

    def mask? r, c, mask
      check_mask mask
      @states[@puz.rc2idx(r, c)] & mask > 0
    end

    def print_states
      puts @states.map { |s| s.to_s(16).rjust(2, '0') }.join.scan(/.{#{@puz.width * 2}}/)
    end
  end

  class RUSR < PuzExtra
    def data= data
      super
      @states = data.unpack 'C*'
    end
  end
end
