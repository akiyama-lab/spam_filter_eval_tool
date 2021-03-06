#!/usr/bin/env ruby

require 'yaml'
require 'nkf'

if ARGV.size < 1
  $stderr.puts "usage: bogofilter -vvv -d . [-p|-s|-n] < input_file | conv_to_fw.rb arff_file [option]"
  $stderr.puts "  option: defalut_value | remove_words"
  $stderr.puts "    default_value: set default value (0.75) if the word in arff_file does not"
  $stderr.puts "                  exist in the word list generated by bogofilter"
  $stderr.puts "    remove_words: remove the word in arff_file which do not exist in the"
  $stderr.puts "                  bogofilter word list"
  exit 1
end

@arff_file = ARGV[0]
@option = ARGV[1] || "remove_words"

@bogofilter_words = {}
@bogofilter_stats = nil

@fw_data_flag = false
@fw_last_data_flag = false
begin
  # parse bogofilter output (stdin)
  while true
    line = $stdin.readline.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: '.')
    # header line of the fw data
    if line.match(/^\s+n\s+pgood\s+pbad\s+fw\s+U/)
      @fw_data_flag = true
    elsif !@fw_data_flag
      next
    end

    if line.match(/^\s+\"([^\s]+)\"\s+(\d+)\s+(\d+\.\d+|nan)\s+(\d+\.\d+|nan)\s+(\d+\.\d+|nan)\s+([\+\-])/)
      word = $1
      @bogofilter_words[word] = {
        "n" => $2,
        "pgood" => $3,
        "pbad" => $4,
        "fw" => $5,
        "u" => $6,
      }
    elsif line.match(/^\s+([^\s]+)\s+(\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s*$/)
      title = $1
      @bogofilter_stats = {
        "N" => $2,
        "P" => $3,
        "Q" => $4,
        "S" => $5
      }
      @fw_last_data_flag = true
    elsif @fw_last_data_flag && line.match(/^\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s*$/)
      @bogofilter_stats = @bogofilter_stats.merge({
        "s" => $1,
        "x" => $2,
        "md" => $3
      })
      break
    end
  end
rescue EOFError => e
rescue => e
  $stderr.puts e.message
  exit 1
end


def conv_to_fw(data_array)
  fw_array = []
  data_array.each do |datum|
    word = @bogofilter_words[@arff_attrs[datum[0].to_i]["word"]]
    if word.nil? || word["fw"] == "nan"
      case @option
      when "default_value"
        fw_array << "#{datum[0]}:0.75"
      when "remove_words"
      end
      next
    end
    fw_array << "#{datum[0]}:#{word["fw"]}"
  end
  fw_array
end

@line_num = 0
@arff_attrs = []
open(@arff_file) do |f|
  begin
    while true do
      @line_num += 1
      line = f.readline

      # read words recorded in ARFF file
      if NKF.nkf("-w", line).match(/^@attribute\s+([^\s]+)\s+([^\s]+)\s*$/)
        word = $1
        type = $2
        @arff_attrs << {
          "word" => word,
          "type" => type
        }
        next
      elsif NKF.nkf("-w", line).match(/^\{([^\}]+)\}$/)
        data = $1
        # output svm light format f(w) values
        data_array = data.split(",").map {|i| i.split(/\s+/)}
        if data_array[0][0] == "0"
          next if data_array[1..-1].empty?
          print "-1 "
          str = conv_to_fw(data_array[1..-1]).join(" ")
          print str
          print "\n"
        else
          print "1 "
          str = conv_to_fw(data_array).join(" ")
          print str
          print "\n"
        end
      end
    end
  rescue EOFError => e
  rescue => e
    $stderr.puts "error #{e.message} at #{@line_num}"
    exit 1
  end
end

# debug
#hash =  {"bogofilter_words" => @bogofilter_words,
# "bogofilter_stats" => @bogofilter_stats,
# "arff_attrs" => @arff_attrs}
#puts hash.to_yaml
#p @bogofilter_words
#p @bogofilter_stats
#p @arff_attrs
