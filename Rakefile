ROOT_PATH = File.expand_path('../',  __FILE__)
require "#{ROOT_PATH}/lib/spam_filter_eval_tool"
include SpamFilterEvalTool
include FileUtils

task :all => [:clear_bogofilter, :clear_svm_results, :clear_svm_corpus]

task :init do
  $config = ConfigFile.new
end

desc "clear fw.txt"
task :clear_fw do
  rm Dir.glob("**/fw.txt"), :force => true
end

desc "clear bogofilter results and db"
task :clear_bogofilter => :init do
  rm "#{$config.params["bogofilter"]["bogofilter_result_file"]}", :force => true
  rm "#{$config.params["bogofilter"]["db_dir"]}/wordlist.db", :force => true
end

desc "clear svm results"
task :clear_svm_results => :init do
  rm "#{$config.params["svm_perf"]["svm_result_file"]}", :force => true
  rm Dir.glob("#{$config.params["spam_assassin_corpus_reader"]["svm_corpus_dir"]}/**/model"), :force => true
  rm Dir.glob("#{$config.params["spam_assassin_corpus_reader"]["svm_corpus_dir"]}/**/precision"), :force => true
end

desc "clear svm corpus"
task :clear_svm_corpus => :init do
  rm_r "#{$config.params["spam_assassin_corpus_reader"]["svm_corpus_dir"]}", :force => true
end
