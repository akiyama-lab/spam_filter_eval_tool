#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ROOT_PATH = File.expand_path('../../',  __FILE__)
require "#{ROOT_PATH}/lib/spam_filter_eval_tool"
include SpamFilterEvalTool

if ARGV.size < 1
  $stderr.puts "usage: conv_svm_result.rb svm_result_file"
  exit 1
end

$svm_result_file = ARGV[0]

$original_data = []
$original_score = []
$min_value = 9999.0
$max_value = -9999.0
$sum = 0.0

$lines = open($svm_result_file).readlines
$lines.each_with_index do |line, i|
  line.match(/^([^\s]+\s+judge=\w+\s+class=\w+\s+score=)(-*\d*\.*\d+)$/)
  $original_data << $1
  $original_score << $2.to_f
  $sum += $original_score[i]
  if $min_value > $original_score[i]
    $min_value = $original_score[i]
  end
  if $max_value < $original_score[i]
    $max_value = $original_score[i]
  end
end

$diff = $max_value - $min_value
$mean = $sum / $lines.size
$lines.each_with_index do |line, i|
  if $original_score[i] <= -1.0
    score = -1.0
  elsif $original_score[i] >= 1.0
    score = 1.0
  else
    score = $original_score[i]
  end
  score = (-1.0 * score + 1.0) / 2.0

  #score = ($max_value - $original_score[i]) / $diff
  puts "#{$original_data[i]}#{"%0.8f" % score}"
end
$stderr.puts "min: #{$min_value}, max: #{$max_value}, diff: #{$diff}"
