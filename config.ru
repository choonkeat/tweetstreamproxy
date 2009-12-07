require 'zlib'
require 'stringio'
require 'net/http'
require 'system_timer'
require 'logger'
Logger.class_eval { alias :write :"<<" } unless Logger.instance_methods.include? "write"
LOGGER = Logger.new("log/#{ENV["RACK_ENV"] || 'development'}.log")
use Rack::CommonLogger, LOGGER

BLOCKED_REGEXP = IO.read("config/blocked_words.regexp").
  split(/\s*[\r\n]+\s*/).
  reject {|s| s == "" }.
  collect {|s| Regexp.new(s, Regexp::IGNORECASE | Regexp::MULTILINE)} rescue BLOCKED_REGEXP = []

require "lib/handle_xml"
use Rack::HandleXml

TWITTER = URI.parse('http://twitter.com/')

# Only look for keys beginning with "HTTP_" and converts
# keys like "HTTP_ACCEPT_CHARSET" to "Accept-Charset"
def get_request_headers(hash)
  hash.inject({}) do |sum, (key, value)|
    case key
    when 'HTTP_HOST'
      sum.merge('Host' => TWITTER.host)
    when /^HTTP_(.+)/
      key = $1.split('_').collect {|x| x.capitalize }.join('-')
      sum.merge(key => value)
    else
      sum
    end
  end
end

# Converts keys like "content-length" to "Content-Length"
def get_response_headers(hash)
  hash.inject({}) do |sum,(lcase_key,v)|
    proper_key = lcase_key.split('-').
                           collect {|x| x.capitalize }.
                           join('-')
    sum.merge(proper_key => v)
  end
end

app = proc do |env|
  request_headers = get_request_headers(env)
  response = Net::HTTP.start(TWITTER.host, TWITTER.port) do |http|
    SystemTimer.timeout(30) do
      case env['REQUEST_METHOD']
      when 'POST'
        request_body = env["rack.input"].read
        env["rack.input"].rewind
        LOGGER.debug "POST #{env['REQUEST_URI']}\n#{request_headers.inspect}\n#{request_body}"
        http.request_post(env['REQUEST_URI'], request_body, request_headers)
      when 'GET'
        LOGGER.debug "GET #{env['REQUEST_URI']}\n#{request_headers.inspect}"
        http.request_get(env['REQUEST_URI'], request_headers)
      else
        # ?
      end
    end
  end

  response_headers = get_response_headers(response.to_hash)
  LOGGER.debug "RESPONSE #{response.code} #{response.message}\n#{response_headers.inspect}"
  return [response.code, response_headers, response.body]
end

run app
