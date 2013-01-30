#!/usr/bin/env ruby

open(ARGV[0]) do |f|
  line_num = 0
  begin
    while true do
      line_num += 1
      line = f.readline
      match = line.match(/^\{([^\}]+)\}\n$/)
      next if match.nil?
      array = match[1].split(",").map {|i| i.split(/\s+/)}
      if array[0][0] == "0"
        next if array[1..-1].empty?
        print "-1 "
        str = array[1..-1].map do |i|
          "#{i[0]}:#{i[1]}"
        end.join(" ")
        print str
        print "\n"
      else
        print "1 "
        str = array.map do |i|
          "#{i[0]}:#{i[1]}"
        end.join(" ")
        print str
        print "\n"
      end
    end
  rescue EOFError => e
  rescue => e
    puts "error #{e} at #{line_num}"
    exit(1)
  end
end
