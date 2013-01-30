#!/usr/bin/env ruby

require 'yaml'
require 'fileutils'

module SpamFilterEvalTool
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
          "svm_result_file" => "svm_result.txt"
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
          @sac_reader.classes.keys.each do |class_name|
            FileUtils.mkpath("#{svm_doc_dir}/#{class_name}")
          end
        end
        command = "ln -s #{src_doc} #{doc.svm_doc}"
        $stderr.puts(command)
        system(command)
        process_weka(svm_doc_dir)
      end
    end

    def generate_span_corpus
      @sac_reader.documents.each_with_index do |doc, di|
        svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
        if !File.exists?(svm_span_corpus_dir)
          FileUtils.mkpath(svm_span_corpus_dir)
          @sac_reader.classes.keys.each do |class_name|
            FileUtils.mkpath("#{svm_span_corpus_dir}/#{class_name}")
          end
        end
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


  class Weka
    # "weka_jar": the location of the Weka jar file
    # "conv_to_svmlight": file format convertor from Weka ARFF to svm_light
    def initialize(options)
      @options = {
        "jar" => "/Applications/MacPorts/Weka.app/Contents/Resources/Java/weka.jar",
        "conv_to_svmlight" => "#{ROOT_PATH}/script/conv_to_svmlight.rb"
      }.merge(options)
    end

    def text_loader(dir)
      command = "java -classpath #{@options["jar"]} weka.core.converters.TextDirectoryLoader -F -D -dir #{dir} > #{dir}/text.arff"
      $stderr.puts(command)
      system(command)
    end

    def word_count(dir)
      command = "java -classpath #{@options["jar"]} weka.filters.unsupervised.attribute.StringToWordVector -C -i #{dir}/text.arff -o #{dir}/#{word_count_fname}"
      $stderr.puts(command)
      system(command)
    end

    def word_count_fname
      "word_count.arff"
    end

    def tf(dir)
      command = "java -classpath #{@options["jar"]} weka.filters.unsupervised.attribute.StringToWordVector -T -i #{dir}/text.arff -o #{dir}/tf.arff"
      $stderr.puts(command)
      system(command)
    end

    def conv_to_svmlight(dir)
      command = "#{@options["conv_to_svmlight"]} #{dir}/tf.arff > #{dir}/#{svmlight_fname}"
      $stderr.puts(command)
      system(command)
    end

    def svmlight_fname
      "tf.txt"
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
      class_name = (spamicity >= threshold) ? "spam" : "ham"
      [class_name, spamicity]
    end

    def evaluate
      @sac_reader.documents.each_with_index do |doc, di|
        svm_span_corpus_dir = @sac_reader.svm_span_corpus_dir(di)
        model = "#{svm_span_corpus_dir}/model"
        precision = "#{svm_span_corpus_dir}/precision"
        # svm_perf_learn
        @svm_perf.learn("#{svm_span_corpus_dir}/#{@weka.svmlight_fname}",
                        model)

        # svm_perf_classify
        @svm_perf.classify("#{doc.svm_doc_dir}/#{@weka.svmlight_fname}",
                           model,
                           precision)

        # extract smapicigy and output to result
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

  class BogofilterEvalExecutor
    def initialize
      @results = []
    end
  end
end
