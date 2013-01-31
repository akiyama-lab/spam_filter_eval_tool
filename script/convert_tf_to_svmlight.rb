#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ROOT_PATH = File.expand_path('../../',  __FILE__)
require "#{ROOT_PATH}/lib/spam_filter_eval_tool"
include SpamFilterEvalTool

$config = ConfigFile.new

$sac_reader = SpamAssassinCorpusReader.new($config.params["spam_assassin_corpus_reader"])
$sac_reader.parse_index!
$weka = Weka.new($config.params["weka"])

$tf_converter = TfConverter.new($sac_reader, $weka)
$tf_converter.conv_to_svmlight
