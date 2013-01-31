#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'yaml'
require 'fileutils'
require 'systemu'
require 'nkf'

module SpamFilterEvalTool
  NKF_SCRIPT = "#{ROOT_PATH}/script/nkf.rb"

  class ConfigFile
    ROOT_PATH = File.expand_path('../../',  __FILE__)
    attr_reader :params

    def initialize(config_path = "#{ROOT_PATH}/config/sf_eval.yml")
      if !File.exists?(config_path)
        $stderr.puts "can not find configuration file: #{config_path}"
        exit 1
      end
      @params = {
        "spam_assassin_corpus_reader" => {
          "corpus_dir" => "#{ROOT_PATH}/files/spamassassin_corpus",
          "svm_corpus_dir" => "#{ROOT_PATH}/files/svm_corpus"
        },
        "svm_corpus_generator" => {
          "word_count" => true,
          "tf" => true
        },
        "weka" => {
          "jar" => "/Applications/MacPorts/Weka.app/Contents/Resources/Java/weka.jar"
        },
        "svm_perf" => {
          "svm_classify" => "#{ENV["HOME"]}/local/bin/svm_perf_classify",
          "svm_learn" => "#{ENV["HOME"]}/local/bin/svm_perf_learn",
          "svm_result_file" => "svm_result.txt",
          "feature_vector" => "tf"
        },
        "bogofilter" => {
          "bogofilter" => "/opt/local/bin/bogofilter",
          "db_dir" => ".",
          "bogofilter_result_file" => "bogofilter_result.txt",
          "conv_to_fw_svmlight" => "#{ROOT_PATH}/script/conv_to_fw.rb",
          "conv_to_fw_svmlight_option" => "remove_words"
        }
      }
      config = YAML.load_file(config_path)
      config.keys.each do |key|
        next if config[key].nil?
        @params[key] = @params[key].merge(config[key])
      end
    end
  end


  class SpamAssassinCorpusReader
    class Document
      attr_accessor :attrs
      def initialize(attributes)
        @attrs = attributes
      end

      def src_doc
        "#{attrs["corpus_dir"]}/#{attrs["corpus_name"]}/#{attrs["number"]}.#{attrs["hash"]}"
      end

      def file
        src_doc
      end

      def svm_doc
        "#{svm_doc_dir}/#{attrs["class"]}/#{attrs["hash"]}"
      end

      def svm_doc_dir
        "#{attrs["svm_corpus_dir"]}/#{attrs["corpus_name"]}/#{attrs["number"]}"
      end
    end

    attr_accessor :documents, :classes

    # options:
    # "corpus_dir": target spam assassin corpus directory
    # "svm_corpus_dir": the directory name for the newly created corpus converted for svm_light
    # "max_doc_num": the maximum number of documents parsed from the index file of spam assassin corpus
    def initialize(options)
      @options = options
      @documents = []
      @classes = {}
    end

    def parse_index!
      open("#{corpus_dir}/index") do |f|
        begin
          while true do
            line = f.readline
            line.match(/^([^\s]+)\s+([^\s]+)/)
            doc = Document.new({
              "corpus_dir" => corpus_dir,
              "svm_corpus_dir" => svm_corpus_dir,
              "class" => $1,
              "path" => $2
            })
            doc.attrs["path"].match(/^([^\/]+)\/(\d+)\.([^\s]+)$/)
            doc.attrs["corpus_name"] = $1
            doc.attrs["number"] = $2
            doc.attrs["hash"] = $3
            @documents << doc
            if @classes[@documents.last.attrs["class"]].nil?
              @classes[@documents.last.attrs["class"]] = 1
            else
              @classes[@documents.last.attrs["class"]] += 1
            end
            if !@options["max_doc_num"].nil?
              if @documents.size >= @options["max_doc_num"]
                break
              end
            end
          end
        rescue EOFError => e
        rescue => e
          $stderr.puts e.message
          exit 1
        end
      end
    end

    def corpus_dir
      File.expand_path(@options["corpus_dir"])
    end

    def svm_corpus_dir
      File.expand_path(@options["svm_corpus_dir"])
    end

    def svm_span_corpus_dir(dir_index)
      first_doc = @documents.first
      last_doc = @documents[dir_index]
      "#{svm_corpus_dir}/svm_span_corpus/#{"%05d" % (dir_index+1)}_#{first_doc.attrs["corpus_name"]}_#{first_doc.attrs["number"]}-#{last_doc.attrs["corpus_name"]}_#{last_doc.attrs["number"]}"
    end

    def svm_span_corpus_doc(dir_index, doc, doc_index)
      "#{svm_span_corpus_dir(dir_index)}/#{doc.attrs["class"]}/#{"%05d" % (doc_index+1)}"
    end
  end

  class SvmCorpusGenerator
    # options:
    # "word_count": true/false (if you want to create word_count.arff, set it to true. default true)
    # "tf": true/false (if you want to create tf.arff and tf.txt, set it to true. default true)
    def initialize(sac_reader, weka, options)
      @sac_reader = sac_reader
      @weka = weka
      @options = options
    end

    def process_weka(target_dir)
      @weka.text_loader(target_dir)
      if @options["word_count"]
        @weka.word_count(target_dir)
      end
      if @options["tf"]
        @weka.tf(target_dir)
      end
      @weka.conv_to_svmlight(target_dir)
    end

    def generate_eval_targets
      @sac_reader.documents.each do |doc|
        src_doc = doc.src_doc
        svm_doc_dir = doc.svm_doc_dir
        if !File.exists?(svm_doc_dir)
          FileUtils.mkpath(svm_doc_dir)
          #@sac_reader.classes.keys.each do |class_name|
          #  FileUtils.mkpath("#{svm_doc_dir}/#{class_name}")
          #end
        end
        #command = "ln -s #{src_doc} #{doc.svm_doc}"
        #$stderr.puts(command)
        #system(command)
        #process_weka(svm_doc_dir)
      end
    end

    def generate_span_corpus
      @sac_reader.documents.each_with_index do |doc, di|
        svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
        if !File.exists?(svm_span_corpus_dir)
          FileUtils.mkpath(svm_span_corpus_dir)
          if di == (@sac_reader.documents.size-1)
            @sac_reader.classes.keys.each do |class_name|
              FileUtils.mkpath("#{svm_span_corpus_dir}/#{class_name}")
            end
          end
        end
        if di == (@sac_reader.documents.size-1)
          (0..di).each do |i|
            doc = @sac_reader.documents[i]
            command = "ln -s #{doc.src_doc} #{@sac_reader.svm_span_corpus_doc(di, doc, i)}"
            $stderr.puts(command)
            system(command)
          end
          process_weka(svm_span_corpus_dir)
        end
      end
    end
  end


  class Weka
    # "weka_jar": the location of the Weka jar file
    # "conv_to_svmlight": file format convertor from Weka ARFF to svm_light
    def initialize(options)
      @options = {
        "jar" => "/Applications/MacPorts/Weka.app/Contents/Resources/Java/weka.jar",
        "conv_to_svmlight" => "#{ROOT_PATH}/script/conv_to_svmlight.rb",
        "sort_text_arff" => "#{ROOT_PATH}/script/sort_text_arff.rb"
      }.merge(options)
    end

    def text_loader(dir)
      command = "java -classpath #{@options["jar"]} weka.core.converters.TextDirectoryLoader -F -D -dir #{dir} | #{@options["sort_text_arff"]} > #{dir}/#{text_fname}"
      $stderr.puts(command)
      system(command)
    end

    def text_fname
      "text.arff"
    end

    def word_count(dir)
      command = "java -classpath #{@options["jar"]} weka.filters.unsupervised.attribute.StringToWordVector -C -i #{dir}/#{text_fname} -o #{dir}/#{word_count_fname}"
      $stderr.puts(command)
      system(command)
    end

    def word_count_fname
      "word_count.arff"
    end

    def tf(dir)
      command = "java -classpath #{@options["jar"]} weka.filters.unsupervised.attribute.StringToWordVector -T -i #{dir}/#{text_fname} -o #{dir}/#{tf_fname}"
      $stderr.puts(command)
      system(command)
    end

    def tf_fname
      "tf.arff"
    end

    def conv_to_svmlight(dir)
      command = "#{NKF_SCRIPT} -w #{dir}/#{tf_fname} | #{@options["conv_to_svmlight"]} > #{dir}/#{svmlight_fname}"
      $stderr.puts(command)
      system(command)
    end

    def svmlight_fname
      "tf.txt"
    end
  end


  class TfConverter
    def initialize(sac_reader, weka)
      @sac_reader = sac_reader
      @weka = weka
      @tf_headers = []
      @tf_values = []
      @svmlight_values = []
    end

    def conv_to_svmlight
      di = @sac_reader.documents.size-1
      svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
      tf_file = "#{svm_span_corpus_dir}/#{@weka.tf_fname}"
      svmlight_file = "#{svm_span_corpus_dir}/#{@weka.svmlight_fname}"
      if !File.exist?(svmlight_file)
        @weka.conv_to_svmlight(svm_span_corpus_dir)
      end
      tf_lines = open(tf_file).readlines
      tf_lines.each do |line|
        match = NKF.nkf("-w", line).match(/^\{([^\}]+)\}$/)
        if match.nil?
          @tf_headers << line
          next
        end
        @tf_values << line
      end
      @svmlight_values = open(svmlight_file).readlines
      # @sac_reader.documents.each_with_index do |doc, di|
      #   @weka.conv_to_svmlight(doc.svm_doc_dir)
      #   svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
      #   @weka.conv_to_svmlight(svm_span_corpus_dir)
      # end
    end

    def split_and_copy
      @sac_reader.documents.each_with_index do |doc, di|
        # create tf.arff for doc
        svm_doc_dir_tf = "#{doc.svm_doc_dir}/#{@weka.tf_fname}"
        $stderr.puts "create #{svm_doc_dir_tf}"
        open(svm_doc_dir_tf, "w") do |f|
          f.puts @tf_headers.join
          f.puts @tf_values[di]
        end
        # create tf.txt for doc
        svm_doc_dir_svmlight = "#{doc.svm_doc_dir}/#{@weka.svmlight_fname}"
        $stderr.puts "create #{svm_doc_dir_svmlight}"
        open(svm_doc_dir_svmlight, "w") do |f|
          f.puts @svmlight_values[di]
        end
        # create tf.arff for span_corpus
        svm_span_corpus_dir_tf = "#{@sac_reader.svm_span_corpus_dir(di)}/#{@weka.tf_fname}"
        $stderr.puts "create #{svm_span_corpus_dir_tf}"
        open(svm_span_corpus_dir_tf, "w") do |f|
          f.puts @tf_headers.join
          f.puts @tf_values[0..di].join
        end
        # create tf.txt for span_corpus
        svm_span_corpus_dir_svmlight = "#{@sac_reader.svm_span_corpus_dir(di)}/#{@weka.svmlight_fname}"
        $stderr.puts "create #{svm_span_corpus_dir_svmlight}"
        open(svm_span_corpus_dir_svmlight, "w") do |f|
          f.puts @svmlight_values[0..di].join
        end
      end
    end
  end


  class SvmPerf
    attr_accessor :params
    def initialize(options)
      @params = {
        "svm_classify" => "#{ENV["HOME"]}/local/bin/svm_perf_classify",
        "svm_learn" => "#{ENV["HOME"]}/local/bin/svm_perf_learn",
        "svm_result_file" => "svm_result.txt"
      }.merge(options)
      @svm_classify = @params["svm_classify"]
      @svm_learn = @params["svm_learn"]
    end

    def classify(data, model, precision)
      command = "#{@svm_classify} #{data} #{model} #{precision}"
      $stderr.puts(command)
      system(command)
    end

    def learn(data, model)
      # FIXME
      # set proper parameters
      command = "#{@svm_learn} -c 0.001 #{data} #{model}"
      $stderr.puts(command)
      system(command)
    end
  end

  class SvmEvalExecutor
    def initialize(sac_reader, weka, svm_perf)
      @sac_reader = sac_reader
      @weka = weka
      @svm_perf = svm_perf
      @svm_result_file = @svm_perf.params["svm_result_file"]
      @results = []
    end

    def result
      "#{doc["path"]} judge=#{doc["class"]} class=#{class_name} score=#{"%0.8f" % spamicity}"
    end

    def threshold(model)
      threshold = 0.0
      open(model) do |f|
        begin
          while true do
            line = f.readline
            if line.match(/(-*\d*\.*\d+)\s+# threshold b, each following line is a SV \(starting with alpha\*y\)/)
              threshold = $1.to_f
              break
            end
          end
        rescue EOFError => e
        rescue => e
          $stderr.puts e.message
          exit 1
        end
      end
      threshold
    end

    def class_and_spamicity(precision, threshold)
      class_name = ""
      spamicity = 0.0
      open(precision) do |f|
        begin
          while true do
            line = f.readline
            if line.match(/(-*\d*\.*\d+)/)
              spamicity = $1.to_f
              break
            end
          end
        rescue EOFError => e
        rescue => e
          $stderr.puts e.message
          exit 1
        end
      end
      class_name = (spamicity <= threshold) ? "spam" : "ham"
      [class_name, spamicity]
    end

    def evaluate
      @sac_reader.documents.each_with_index do |doc, di|
        next if di == 0
        svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di-1)
        model = "#{svm_span_corpus_dir}/model"
        precision = "#{svm_span_corpus_dir}/precision"
        # svm_perf_learn
        case @svm_perf.params["feature_vector"]
        when "tf"
          @svm_perf.learn("#{svm_span_corpus_dir}/#{@weka.svmlight_fname}",
                          model)
        when "fw"
          next if di < 3
          @svm_perf.learn("#{svm_span_corpus_dir}/fw.txt",
                          model)
        end

        # svm_perf_classify
        case @svm_perf.params["feature_vector"]
        when "tf"
          @svm_perf.classify("#{doc.svm_doc_dir}/#{@weka.svmlight_fname}",
                             model,
                             precision)
        when "fw"
          next if di < 3
          @svm_perf.classify("#{doc.svm_doc_dir}/fw.txt",
                             model,
                             precision)
        end

        # extract smapicity and output to result
        threshold = threshold(model)
        class_name, spamicity = class_and_spamicity(precision, threshold)
        @results << "#{doc.attrs["path"]} judge=#{doc.attrs["class"]} class=#{class_name} score=#{"%0.8f" % spamicity}"
      end
    end

    def output_result
      open(@svm_result_file, "a+") do |f|
        f.puts @results.join("\n")
      end
    end
  end

  class Bogofilter
    attr_accessor :params
    def initialize(options)
      @params = {
        "bogofilter" => "/opt/local/bin/bogofilter",
        "db_dir" => ".",
        "bogofilter_result_file" => "bogofilter_result.txt"
      }.merge(options)
      @bogofilter = @params["bogofilter"]
    end

    def classify(file)
      command = "#{@bogofilter} -vvv -d #{@params["db_dir"]} -p < #{file} | #{NKF_SCRIPT} -w"
      $stderr.puts(command)
      `#{command}`
    end

    def learn(class_name, file)
      command = ""
      case class_name
      when "spam"
        command = "#{@bogofilter} -vvv -d #{@params["db_dir"]} -s < #{file} | #{NKF_SCRIPT} -w"
      when "ham"
        command = "#{@bogofilter} -vvv -d #{@params["db_dir"]} -n < #{file} | #{NKF_SCRIPT} -w"
      end
      $stderr.puts(command)
      `#{command}`
    end
  end

  class BogofilterEvalExecutor
    def initialize(sac_reader, weka, bogofilter, min_learn = 2)
      @sac_reader = sac_reader
      @weka = weka
      @bogofilter = bogofilter
      @bogofilter_result_file = @bogofilter.params["bogofilter_result_file"]
      @conv_to_fw_svmlight = @bogofilter.params["conv_to_fw_svmlight"]
      @conv_to_fw_svmlight_option = @bogofilter.params["conv_to_fw_svmlight_option"]
      @min_learn = min_learn
      @results = []
    end

    def conv_to_fw_svmlight(dir, tf_file = "tf.arff", fw_file = "fw.txt")
      # for debug
      #command = "#{NKF_SCRIPT} -w > #{dir}/#{fw_file}"
      command = "#{@conv_to_fw_svmlight} #{dir}/#{tf_file} #{@conv_to_fw_svmlight_option} > #{dir}/#{fw_file}"
      $stderr.puts(command)
      command
    end

    def evaluate
      @sac_reader.documents.each_with_index do |doc, di|
        classify_result = nil
        # does not execute classify before finishing to learn document more than @min_learn
        if di >= @min_learn
          # classify
          class_name = ""
          spamicity = 0.0
          classify_result = @bogofilter.classify(doc.file)
          # for debug
          $stderr.puts classify_result
          #classify_result.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: '.').split("\n").each do |line|
          classify_result.split("\n").each do |line|
            match1 = line.match(/.*X-Bogosity: (.*), tests.*/)
            if match1
              class_name = ($1.downcase == "spam") ? "spam" : "ham"
            end
            match2 = line.match(/tests.*, spamicity=(.*), version.*/)
            if match2
              spamicity = $1.to_f
            end
            if match1 || match2
              break
            end
          end
          class_name = "ham" if class_name.empty?
          @results << "#{doc.attrs["path"]} judge=#{doc.attrs["class"]} class=#{class_name} score=#{"%0.8f" % spamicity}"
          svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
          status, stdout, stderr = systemu conv_to_fw_svmlight(svm_span_corpus_dir, @weka.tf_fname), 0=>classify_result
          $stderr.puts [status, stdout, stderr].inspect
        end

        # learn
        learn_result = @bogofilter.learn(doc.attrs["class"], doc.file)
        # for debug
        $stderr.puts learn_result
        status, stdout, stderr = systemu conv_to_fw_svmlight(doc.svm_doc_dir, @weka.tf_fname), 0=>classify_result
        $stderr.puts [status, stdout, stderr].inspect
      end
    end

    def output_result
      open(@bogofilter_result_file, "a+") do |f|
        f.puts @results.join("\n")
      end
    end
  end
end
