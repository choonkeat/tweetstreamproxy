require 'lib/handle_tweets'
require "lib/handle_base"
require 'stringio'
require 'hpricot'
require 'hpricot/xchar' # Hpricot.xs
require 'zlib'

module Rack
  class HandleXml < HandleBase
    include HandleTweets
    def handle_response(status, headers, body)
      return super unless @was_get_request
      return super unless headers['Content-Type'].to_s =~ /\bxml\b/
      is_gzipped = (headers['Content-Encoding'].to_s == 'gzip')
      plain_content = is_gzipped ? Zlib::GzipReader.new(StringIO.new(body)).read : body
      doc = Hpricot(plain_content)
      (doc/"status").each do |ele|
        (ele/"text").each do |textele|
          inner_html = textele.inner_html
          if BLOCKED_REGEXP.find {|r| r.match(inner_html) }
            ele.set_attribute("deleted", "1")
            LOGGER.debug "DELETED #{inner_html.inspect}"
          elsif inner_html =~ /\b(([\w-]+:\/\/?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|\/)))/mi
            # http://daringfireball.net/2009/11/liberal_regex_for_matching_urls
            found_url = $1
            long_url = self.expand_url(found_url).gsub(/[\s\r\n]+/m, ' ').strip
            LOGGER.debug "tweet was    : #{textele.inner_html}"
            textele.inner_html = inner_html.gsub(found_url, Hpricot.xs(long_url))
            LOGGER.debug "tweet becomes: #{textele.inner_html}"
          end
        end
      end
      (doc/"status[@deleted='1']").remove
      body = if is_gzipped
        sio = StringIO.new "", "r+"
        Zlib::GzipWriter.wrap(sio) {|io| io.write(doc.to_s)}
        sio.string
      else
        doc.to_s
      end
      headers['Content-Length'] = [body.length.to_s]
      return [status, headers, body]
    rescue Exception
      LOGGER.error $!
      return [status, headers, body]
    end
  end
end