require 'rubygems'
require 'friendly'
Friendly.configure(YAML.load(IO.read("config/database.yml"))[ENV["RACK_ENV"] || 'development'])

class UrlCache
  include Friendly::Document
  attribute :short_url, String
  attribute :real_url,  String

  indexes :short_url
  indexes :created_at
end

Friendly.create_tables!
