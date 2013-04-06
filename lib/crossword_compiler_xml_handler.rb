require 'nokogiri'

module Puzrb
  # For reading puzzle files in the Crossword Compiler XML format.
  class CrosswordCompilerXMLHandler
    # We have namespaces in the document.
    # We could strip them with .remove_namespaces! but this code is mostly a
    # programming exercise and as such shouldn't employ shortcuts so it can be
    # referred to in the future.
    CROSSWORD_COMPILER_NS = 'http://crossword.info/xml/crossword-compiler-applet'
    RECTANGULAR_PUZZLE_NS = 'http://crossword.info/xml/rectangular-puzzle'

    # Parses crossword compiler XML and returns a Puzrb::Puzzle instance.
    def self.read io
      doc = Nokogiri::XML open(io)
      rect_puz = doc.at_xpath '//ns:rectangular-puzzle', 'ns' => RECTANGULAR_PUZZLE_NS

      grid = rect_puz.at_xpath '//ns:grid', 'ns' => RECTANGULAR_PUZZLE_NS
      width = grid.at_xpath '@width'
      height = grid.at_xpath '@height'
      raise "width and height aren't specified" unless width && height

      puz = Puzzle.new_blank width.value.to_i, height.value.to_i

      # Set metadata
      meta = rect_puz.at_xpath 'ns:metadata', 'ns' => RECTANGULAR_PUZZLE_NS
      if meta
        %w(title creator copyright description).each do |attr|
          meta.at_xpath("ns:#{attr}", 'ns' => Puzrb::CrosswordCompilerXMLHandler::RECTANGULAR_PUZZLE_NS)
          next unless meta
          text = meta.text || ''
          attr = 'author' if attr == 'creator'
          text.strip! #force_encoding 'ISO-8859-1'
          puz.instance_variable_set "@#{attr}", text
        end
      else
        puts 'INFO: no metadata found in puzzle'
      end

      cells = grid.xpath 'ns:cell', 'ns' => RECTANGULAR_PUZZLE_NS
      cells.each do |cell|
        # Note that XML x,y is 1-based but our puzzle row,col is 0-based
        x = cell.at_xpath('@x').value.to_i - 1
        y = cell.at_xpath('@y').value.to_i - 1
        type_attr = cell.at_xpath('@type')
        # Skip blocks
        if type_attr && type_attr.value == 'block'
          next
        end
        # Set the solution letter
        letter = cell.at_xpath('@solution').value
        puz.set_solution_letter x, y, letter
        # Set the state letter to default hyphen
        # Change the state array directly because we don't want the puzzle to
        # check whether the letter is correct or not.
        puz.instance_variable_get(:@state)[puz.rc2idx(x, y)] = '-'
      end

      # Get the clues
      clues = rect_puz.xpath('//ns:clue', 'ns' => RECTANGULAR_PUZZLE_NS).map do |c|
        c.text #.force_encoding 'ISO-8859-1'
      end
      puz.instance_variable_set :@n_clues, clues.length
      puz.instance_variable_set :@clues, clues

      # Create the mapping of clues to letters and letters to clues.
      #
      # Note that the XML specifies where words are and which clue each
      # letter is for. However we have to derive this manually for
      # the normal binary format puzzles, so just use that here as it sets
      # up all the necessary variables.
      puz.map_clues

      # Set checksums
      [:cib_checksum, :board_checksum, :masked_low_checksums, :masked_high_checksums].each do |cs|
        checksum = puz.calculate_checksum cs
        puz.instance_variable_set "@#{cs.to_s}".to_sym, checksum
      end

      puz
    end
  end
end
