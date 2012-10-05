require_relative 'puz'
require 'awesome_print'

ARGV.each do |f|
#Dir.glob('puzzles/*puz').each do |f|
  puts "Loading #{f}"
  p = Puzrb::Puzzle.load open(f)
  puts "Loaded #{f}\n\n"
#  ap p
  #p.print_solution
  #p.print_state
  puts "\n\n"
end
