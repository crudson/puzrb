class Puz
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

  def initialize
  end

  def self.load io
    p = Puz.new
    p._load io
ap p
    p.verify
    p
  end

  def print_solution
    puts @solution.scan(/.{#{@width}}/)
  end

  def print_state
    puts @state.scan(/.{#{@width}}/)
  end

  # Read in a .puz file
  # This does not validate the integrity of the data with respect to checksums.
  # see #verify
  def _load io
    @raw = io.read #.unpack('v*')
    io.rewind

    file_magic_idx = @raw.index "ACROSS&DOWN"
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

    @clues = []
    extra = nil
    io.read.force_encoding('ISO-8859-1').split("\0").each_with_index do |s,i|
      puts "#{i}:#{s}"
      case i
        when 0; @title = s
        when 1; @author = s
        when 2; @copyright = s
        when 3..(3+@n_clues-1); @clues << s
        when 3+@n_clues; @notes = s
        else
      end
    end
  end

  def verify
    # n clues
    raise "Wrong number of clues:#{@clues.length} expected:#{@n_clues}" unless @clues.length == @n_clues

    # CIB checksum
    cib_cs = cs = checksum [@width,@height,@n_clues,@bitmask,@scrambled_tag].pack('CCvvv')
    raise "Bad CIB checksum:#{cs} vs orig:#{@cib_checksum}" unless cs == @cib_checksum
    puts "CIB checksum is good:#{cs}"

    # Primary board checksum
    cs = checksum @solution, cs
    cs = checksum @state, cs
    [:@title, :@author, :@copyright].each do |a|
      v = instance_variable_get a
      cs = checksum("#{v}\0", cs) unless v.nil? || v.empty?
    end
    cs = @clues.reduce(cs) { |p,c| checksum c, p }
    cs = checksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
    raise "Bad checksum:#{cs} vs orig:#{@checksum}" unless cs == @checksum
    puts "Checksum is good:#{cs}"

    # Masked checksums
    sol_cs = checksum @solution
    grd_cs = checksum @state
    cs = 0x0
    [:@title, :@author, :@copyright].each do |a|
      v = instance_variable_get a
      cs = checksum("#{v}\0", cs) unless v.nil? || v.empty?
    end
    cs = @clues.reduce(cs) { |p,c| checksum c, p }
    cs = checksum("#{@notes}\0", cs) unless @notes.nil? || @notes.empty?
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
  end

  # https://code.google.com/p/puz/wiki/FileFormat#Checksums
  def checksum data, cksum=0
    data.each_byte.reduce(cksum) do |p,c|
      (c + ((p & 0x1 == 0) ? (p >> 1) : (p >> 1 | 0x8000))) & 0xffff
    end
  end
end

class PuzExtra
  attr_accessor :title
  attr_accessor :length
  attr_accessor :checksum
  attr_accessor :data
end
