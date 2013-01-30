# SPAM Filter Evaluation Tool

This repository just provide several scripts to support evaluations of spam filter using TREC Spam Filter Evaluation Toolkit. Currently, it just add a support of SVM Light evaluation.

# Getting Started

## Installation

First of all, clone the repository.

    % git clone https://github.com/akiyama-lab/spam_filter_eval_tool.git
    % cd spam_filter_eval_tool

## Configuration

Create and edit configuration file.

    % cp config/sf_eval.yml.sample config/sf_eval.yml
    % vi config/sf_eval.yml

corpus_dir, svm_corpus_dir, jar (weka), svm_perf_classify, svm_perf_learn should be modified to fit your environment.

## How to run

Generate a corpus for SVM Light

    % ./script/generate_svm_corpus.rb

Evaluate SVM Light

    % ./script/eval_svmlight.rb
