module Puzrb
  module Checksum
    def chksum data, cksum=0
      data.each_byte.reduce(cksum) do |p,c|
        (c + ((p & 0x1 == 0) ? (p >> 1) : (p >> 1 | 0x8000))) & 0xffff
      end
    end
  end
end
