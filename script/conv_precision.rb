#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ROOT_PATH = File.expand_path('../../',  __FILE__)
require "#{ROOT_PATH}/lib/spam_filter_eval_tool"
include SpamFilterEvalTool

if ARGV.size < 2
  $stderr.puts "usage: conv_precision.rb model precision"
  exit 1
end

$model = ARGV[0]
$precision = ARGV[1]

$config = ConfigFile.new

$sac_reader = SpamAssassinCorpusReader.new($config.params["spam_assassin_corpus_reader"])
$sac_reader.parse_index!
$weka = Weka.new($config.params["weka"])
$svm_perf = SvmPerf.new($config.params["svm_perf"])
$svm_eval_exec = SvmEvalExecutor.new($sac_reader, $weka, $svm_perf)
threshold = $svm_eval_exec.threshold($model)

$lines = open($precision).readlines
$sac_reader.documents.each_with_index do |doc, di|
  exit 0 if di >= $lines.size
  spamicity = $lines[di].match(/(-*\d*\.*\d+)/)[1].to_f
  class_name = (spamicity <= threshold) ? "spam" : "ham"
  puts "#{doc.attrs["path"]} judge=#{doc.attrs["class"]} class=#{class_name} score=#{"%0.8f" % spamicity}"
end
