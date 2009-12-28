require 'lib/handle_tweets'
require "lib/handle_base"
require 'stringio'
require 'json'
require 'zlib'

module Rack
  class HandleJson < HandleBase
    include HandleTweets
    def handle_response(status, headers, body)
      return super unless @was_get_request
      return super unless headers['Content-Type'].to_s =~ /\b(javascript|json)\b/
      is_gzipped = (headers['Content-Encoding'].to_s == 'gzip')
      plain_content = is_gzipped ? Zlib::GzipReader.new(StringIO.new(body)).read : body
      case tweets = JSON.parse(plain_content)
      when Array
        tweets.each do |tweet|
          next unless tweet["text"]
          if BLOCKED_REGEXP.find {|r| r.match(tweet["text"]) }
            tweet["deleted"] = true
            LOGGER.debug "DELETED #{tweet["text"].inspect}"
          elsif tweet["text"] =~ /\b(([\w-]+:\/\/?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|\/)))/mi
            # http://daringfireball.net/2009/11/liberal_regex_for_matching_urls
            found_url = $1
            long_url = self.expand_url(found_url).gsub(/[\s\r\n]+/m, ' ').strip
            LOGGER.debug "tweet was    : #{tweet["text"]}"
            tweet["text"] = tweet["text"].gsub(found_url, Hpricot.xs(long_url))
            LOGGER.debug "tweet becomes: #{tweet["text"]}"
          end
        end
        tweets.reject! {|tweet| tweet["deleted"] }
      end
      body = if is_gzipped
        sio = StringIO.new "", "r+"
        Zlib::GzipWriter.wrap(sio) {|io| io.write(tweets.to_json)}
        sio.string
      else
        doc.to_s
      end
      headers['Content-Length'] = [body.length.to_s]
      return [status, headers, body]
    rescue JSON::ParserError
      LOGGER.error $!.to_s
      LOGGER.error plain_content
      return [status, headers, body]
    rescue Exception
      LOGGER.error $!
      return [status, headers, body]
    end
  end
end