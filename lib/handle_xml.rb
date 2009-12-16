require "lib/handle_base"
require "addressable/uri"
require 'stringio'
require 'hpricot'
require 'hpricot/xchar' # Hpricot.xs
require 'zlib'

module Rack
  class HandleXml < HandleBase
    def handle_request(env)
      @was_get_request = env['REQUEST_METHOD'] == 'GET'
      @user_agent = env['HTTP_USER_AGENT']
      super
    end
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

    def quick_get(url)
      LOGGER.debug "fetching #{url} ..."
      uri = Addressable::URI.parse(url.match(/^\w+\:\/\//) ? url : "http://#{url}")
      SystemTimer.timeout(10) do
        Net::HTTP.start(uri.host, uri.port) do |http|
          http.get([(uri.path == '' ? '/' : uri.path), uri.query].compact.join('?'), "User-Agent" => @user_agent)
        end
      end
    end
    def get_title_from(html)
      doc = Hpricot(html)
      title = ''
      (doc/"meta[@property='media:title']").each {|ele| title ||= (ele && ele.get_attribute("content").to_s.strip) } if title == ''
      (doc/"title:first").each {|ele| title = (ele && ele.inner_text.to_s.strip) } if title == ''
      (doc/"h1:first").each {|ele| title = (ele && ele.inner_text.to_s.strip) } if title == ''
      title.to_s
    rescue
      LOGGER.error $!
      ''
    end
    def expand_url(found_url)
      res = self.quick_get(found_url)
      long_url = Addressable::URI.join(found_url, res['location'] || found_url).to_s
      counter = 0
      while res['location'].to_s.strip != "" && counter < 3
        long_url = Addressable::URI.join(long_url, res['location']).to_s
        res = self.quick_get(long_url)
        counter+=1
      end
    rescue Exception
      LOGGER.error $!
    ensure
      title = self.get_title_from(res.body) if res && res.body
      return (title == '') ? long_url : "#{long_url} [#{title}]"
    end
  end
end