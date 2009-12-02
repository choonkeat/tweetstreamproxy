require "lib/handle_base"
require 'stringio'
require 'hpricot'
require 'zlib'

module Rack
  class HandleXml < HandleBase
    def handle_response(status, headers, body)
      return super unless headers['Content-Type'].to_s =~ /\bxml\b/
      is_gzipped = (headers['Content-Encoding'].to_s == 'gzip')
      plain_content = is_gzipped ? Zlib::GzipReader.new(StringIO.new(body)).read : body
      doc = Hpricot(plain_content)
      (doc/"status").each do |ele|
        if (ele/"text").inner_html =~ /^i just.+@foursquare/mi
          ele.set_attribute("deleted", "1")
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
    rescue
      LOGGER.debug $!
      LOGGER.debug $!.join("\n")
      return [status, headers, body]
    end
  end
end