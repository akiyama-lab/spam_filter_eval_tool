# SPAM Filter Evaluation Tool

This repository just provide several scripts to support evaluations of spam filter using TREC Spam Filter Evaluation Toolkit. Currently, it just add a support of SVM Light evaluation.

# Getting Started

## Installation

First of all, clone the repository.

    % git clone https://github.com/akiyama-lab/spam_filter_eval_tool.git
    % cd spam_filter_eval_tool
    % bundle install

You need to patch bogofilter before using with this tool.

    % cd ..
    % tar jxvf bogofilter-1.2.3.tar.bz
    % cd bogofilter-1.2.3
    % patch -p1 < ../spam_filter_eval_tool/patch/patch-for-bogofilter-1.2.3.patch
    % ./configure --with-database=sqlite3 --with-libsqlite3-prefix=/opt/local --with-libiconv-prefix=/opt/local --without-libdb-prefix --without-libqdbm-prefix --prefix=$HOME/local
    % make
    % make install

## Configuration

Create and edit configuration file.

    % cp config/sf_eval.yml.sample config/sf_eval.yml
    % vi config/sf_eval.yml

corpus_dir, svm_corpus_dir, jar (weka), svm_classify, svm_learn should be modified to fit your environment.

## How to run

Generate a corpus for SVM Light

    % ./script/generate_svm_corpus.rb
    % ./script/convert_tf_to_svmlight.rb

Evaluage Bogofilter and create fw.txt files

    % ./script/eval_bogofilter.rb

Evaluate SVM Light

    % ./script/eval_svmlight.rb

Convert SVM Light results (svm score to spamicity)

    % ./script/conv_svm_result.rb svm_result.txt > svm_result.spamicity

## How to clear data

You can use Rake tasks to clear generated data.

    % rake --tasks
