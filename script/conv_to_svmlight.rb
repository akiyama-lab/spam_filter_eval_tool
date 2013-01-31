#!/usr/bin/env ruby

line_num = 0
begin
  while line = ARGF.gets
    line_num += 1
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
