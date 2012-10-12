module Puzrb
  # Base class for extra sections.
  class Extra
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

    def verify
      raise "Bad length for extra:#{name}, length:#{data.length} expected:#{length}" unless
        data.length == length + 1
#      puts "Extra:#{name} length is good:#{length}"
      cs = chksum data[0..-2] # data was read with \0, so strip for checksum
      raise "Bad extra:#{name} checksum:#{cs} expected:#{checksum}" unless
        cs == checksum
#      puts "Extra:#{name} checksum is good:#{cs}"
    end

    # Subclasses must implement this.
    def serialize_data
      raise NotImplementedError
    end

    # Pack contents.
    # Updates checksum and length.
    # #serialize_data will be called first, so ensure it's implemented.
    def serialize
      serialize_data
      @length = data[0..-2].length
      @checksum = chksum data[0..-2]
      name + [length, chksum(data[0..-2])].pack('vv') + data
    end
  end

  # Where rebuses are located in the puzzle.
  class GRBS < Extra
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

    # Print whole grid showing rebus numbers.
    def print_board
      puts @board.map { |s| s.to_s(16).rjust(2, '0') }.join.scan(/.{#{@puz.width * 2}}/)
    end

    # Set rebus number for the given row,col.
    def set_rebus_n r, c, rebus_n
      @board[r * @puz.width + c] = rebus_n + 1
    end

    def serialize_data
      @data = @board.pack('C*') + '\0'
    end
  end

  # Rebuses in the solution.
  # Rebus numbers in GBRS must correspond to numbers here (-1).
  class RTBL < Extra
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

    # Return all rebuses.
    # Clone to restrict mutability to this class.
    def rebuses
      @rebuses.clone
    end

    def set_rebus_for_n n, val
      current = rebus_for_n n
      if current
        current[:val] = val
      else
        @rebuses << {:n => n, :val => val}
      end
    end

    def serialize_data
      @data = @rebuses.map { |r| "#{r[:n].to_s.rjust(2, '0')}:#{r[:val]};" }.pack('Z*') + '\0'
    end
  end

  # Timer information.
  class LTIM < Extra
    attr_accessor :time_elapsed

    def data= data
      super
      @time_elapsed, @stopped = data.scanf '%d,%d'
    end

    def set_time_elapsed secs
      @time_elapsed = secs
    end

    # Note that this just sets the state, it is up to some external object to maintain a timer.
    def start
      @stopped = 0
    end

    # Note that this just sets the state, it is up to some external object to maintain a timer.
    def stop
      @stopped = 1
    end

    def serialize_data
      @data = "#{@time_elapsed},#{@stopped}\0"
    end
  end

  # Flags for squares in the current state.
  class GEXT < Extra
    PREV_INCORRECT = 0x10 # square was previously marked incorrect
    CURR_INCORRECT = 0x20 # square is currently marked incorrect
    REVEALED       = 0x40 # contents of square were given
    CIRCLED        = 0x80 # square is circled. 

    # GEXT data is a grid of byte bitmasks matching (none or a mixture of) the
    # constants in this class.
    def data= data
      super
      @states = data.unpack 'C*'
    end

    def check_mask mask
      raise "Bad mask:#{mask}" unless [PREV_INCORRECT, CURR_INCORRECT, REVEALED, CIRCLED].include?(mask)
    end

    # blank out all masks
    def blank!
      @states = [0] * (@puz.width * @puz.height)
    end

    def set_mask r, c, mask
      check_mask mask
      idx = @puz.rc2idx(r, c)
      @states[idx] |= mask
      # TODO: prevent going to PREV_INCORRECT or CURR_INCORRECT if currently have REVEALED set?
      #       AcrossLite prevents this.
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

    def serialize_data
      @data = @states.pack('C*') + '\0'
    end
  end

  # User entered values for rebus squares.
  class RUSR < Extra
    def data= data
      super
      @states = data.unpack 'C*'
    end

    def serialize_data
      @data = @states.pack('C*') + '\0'
    end
  end
end
