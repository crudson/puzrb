require_relative 'puz'
require 'awesome_print'

ARGV.each do |f|
#Dir.glob('puzzles/*puz').each do |f|
  puts "Loading #{f}"
  p = Puz.load open(f)
  puts "Loaded #{f}"
  puts "\n\n"
  gets
end
#ap p
#p.print_solution
#p.print_state
