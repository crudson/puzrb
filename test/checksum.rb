require 'test/unit'
require_relative '../lib/puzrb'
require_relative 'helper'

class TestChecksum < Test::Unit::TestCase
  include Puzrb::Checksum
  include Puzrb::Test::Helper

  # Simple checksum test
  def test_checksum_string
    s = 'this_is_a_test'
    assert_equal chksum(s), 26465
    assert_not_equal chksum(s), 123456
  end

  # Load a valid puzzle file and test all the checksums within it against our checksum method.
  # Use _load, so as to not perform automatic verification. We have other tests for that.

  def test_cib_checksum_from_file
    p = puzzle_unverified
    assert_equal p.cib_checksum, p.calculate_checksum(:cib_checksum)
  end

  def test_board_checksum_from_file
    p = puzzle_unverified
    assert_equal p.board_checksum, p.calculate_checksum(:board_checksum)
  end

  def test_masked_low_checksums_from_file
    p = puzzle_unverified
    assert_equal p.masked_low_checksums, p.calculate_checksum(:masked_low_checksums)
  end

  def test_masked_high_checksums_from_file
    p = puzzle_unverified
    assert_equal p.masked_high_checksums, p.calculate_checksum(:masked_high_checksums)
  end

  def test_bad_checksum_type
    p = puzzle_unverified
    assert_raise(RuntimeError) { p.calculate_checksum(:illegal_checksum) }
  end

  def test_verify_checksum_error_raise
    p = puzzle_unverified
    assert_nothing_raised { p.verify_checksum(:cib_checksum) }
    p = p.clone
    p.instance_variable_set :@cib_checksum, 123
    assert_raise(RuntimeError) {  p.verify_checksum(:cib_checksum) }
  end

  # load verified so we know verification works, change attributes and ensure it then fails
  def test_verify_n_clues
    p = puzzle.clone
    p.instance_variable_set :@n_clues, p.clues.length - 2
    assert_raise(RuntimeError) { p.verify }
  end

  def test_verify_checksums
    %w(cib_checksum board_checksum masked_low_checksums masked_high_checksums).each do |c|
      p = puzzle.clone
      p.instance_variable_set "@#{c}".to_sym, 1
      assert_raise(RuntimeError) { p.verify }
    end
  end
end
