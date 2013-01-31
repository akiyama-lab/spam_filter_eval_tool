#!/usr/bin/env ruby

require 'nkf'

line_num = 0
@headers = []
@documents = {}
begin
  while line = ARGF.gets
    line_num += 1
    match = NKF.nkf("-w", line).match(/,(spam|ham)\/(\d{5}),(spam|ham)$/)
    if match.nil?
      @headers << line
      next
    end
    file = match[2]
    @documents[file] = line
  end
rescue EOFError => e
rescue => e
  puts "error #{e} at #{line_num}"
  exit(1)
end
puts @headers.join
puts @documents.sort.map {|i| i[1]}.join
