require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'rdoc/task'

ENV['RAILS_ENV'] = "test"
require File.expand_path("#{File.dirname(__FILE__)}/config/solr_environment")

Dir["#{File.dirname(__FILE__)}/lib/tasks/*.rake"].sort.each { |ext| load ext }

