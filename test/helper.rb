module Puzrb
  module Test
    module Helper
      def puzzle
        @puzzle ||= load_verify
      end

      def puzzle_scrambled
        @puzzle_scrambled ||= load_scrambled
      end

      def puzzle_unverified
        @puzzle_unverified ||= load_no_verify
      end

      def load_verify
        f = File.join(File.dirname(__FILE__), '..', 'puzzles', 'pi120909.puz')
        Puzrb::Puzzle.load(open(f))
      end

      def load_no_verify
        f = File.join(File.dirname(__FILE__), '..', 'puzzles', 'pi120909.puz')
        Puzrb::Puzzle.new._load(open(f))
      end

      def load_scrambled
        f = File.join(File.dirname(__FILE__), '..', 'puzzles', 'nyt_with_shape.puz')
        Puzrb::Puzzle.new._load(open(f))
      end
    end
  end
end
