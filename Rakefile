# -*- coding: utf-8 -*-
require 'rubygems'
require 'bundler/setup'
require 'rake'
require 'rake/testtask'

require 'github_api'
require 'trello'
require 'dotenv'
require 'active_support/all'

Dotenv.load # load the .env file

require_relative 'lib/gitthello.rb'
Dir[File.join(File.dirname(__FILE__), 'lib', 'gitthello', 'tasks','*.rake')].each { |f| load f }

task :default => :test

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end
