require 'test/unit'
require 'stringio'

require_relative '../lib/puzrb'
require_relative 'helper'

class TestPuzzle < Test::Unit::TestCase
  include Puzrb::Test::Helper

  def test_load
    assert_nothing_raised { load_verify }
  end

  def test_load_invalid
    assert_raise(RuntimeError) { Puzrb::Puzzle.load(StringIO.new('junk')) }
  end

  def test_scrambled
    assert puzzle_scrambled.is_scrambled?
    assert !puzzle.is_scrambled?
  end

  def test_rc2idx
    p = puzzle
    assert_equal p.rc2idx(0, 0), 0
    assert_equal p.rc2idx(p.height - 1, p.width - 1), (p.height * p.width) - 1
  end

  def test_idx2rc
    p = puzzle
    assert_equal p.idx2rc(0), [0, 0]
    assert_equal p.idx2rc((p.height * p.width) - 1), [p.height - 1, p.width - 1]
  end

  def test_is_black?
    p = puzzle
    assert !p.is_black?(0,0)
    assert p.is_black?(0,6)
  end

  def test_read_string
    p = puzzle
    io = StringIO.new "abc\0def\0"
    assert_equal p.read_string(io), "abc"
    # Shouldn't return the NUL at end
    assert_not_equal p.read_string(io), "def\0"
  end

  def test_clues_mapped
    p = puzzle
    assert_equal p.across_clues.length + p.down_clues.length, p.n_clues
    # have a clue for each non-black square?
    (0...p.height).each do |r|
      (0...p.width).each do |c|
        if !p.is_black?(r,c)
          assert_not_nil p.clue_map[p.rc2idx(r, c)]
        end
      end
    end
  end

  def test_solution_letter_at
    assert_equal puzzle.solution_letter_at(0,0), 'S'
  end

  def test_letter_at
    assert_equal puzzle.letter_at(0,0), 'S'
  end

  def test_solution_word_at
    assert_equal puzzle.solution_word_at(0,0,:across), 'STUMPS'
    assert_equal puzzle.solution_word_at(0,0,:down), 'STP'
  end

  def test_word_at
    assert_equal puzzle.word_at(0,0,:across), 'STUMPS'
    assert_equal puzzle.word_at(0,0,:down), 'STP'
  end

  def test_set_letter_at
    p = puzzle.clone
    p.set_letter_at 0, 0, 'A'
    assert_equal p.letter_at(0,0), 'A'
  end

  def test_check_letter_sets_incorrect_flag
    p = puzzle.clone
    p.set_letter_at 0, 0, 'A'
    p.check_letter 0, 0
    assert p.gext.mask?(0, 0, Puzrb::GEXT::CURR_INCORRECT)
  end

  def test_set_letter_at_updates_incorrect_flag
    p = puzzle.clone
    p.set_letter_at 0, 0, 'A'
    p.check_letter 0, 0
    p.set_letter_at 0, 0, 'B'
    assert p.gext.mask?(0, 0, Puzrb::GEXT::PREV_INCORRECT)
  end
end



