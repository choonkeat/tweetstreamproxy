require "addressable/uri"

module HandleTweets
  def handle_request(env)
    @was_get_request = env['REQUEST_METHOD'] == 'GET'
    @user_agent = env['HTTP_USER_AGENT']
    super
  end
  def quick_get(url)
    if cache = UrlCache.first(:short_url => url)
      return cache.real_url
    else
      LOGGER.debug "fetching #{url} ..."
      uri = Addressable::URI.parse(url.match(/^\w+\:\/\//) ? url : "http://#{url}")
      res = SystemTimer.timeout(5) do
        Net::HTTP.start(uri.host, uri.port) do |http|
          http.get([(uri.path == '' ? '/' : uri.path), uri.query].compact.join('?'), "User-Agent" => @user_agent)
        end
      end
      return Addressable::URI.join(url, res['location'] || url).to_s.strip, res
    end
  rescue Exception
    return url.to_s.strip
  end
  def get_title_from(html)
    doc = Hpricot(html)
    title = ''
    (doc/"meta[@property='media:title']").each {|ele| title ||= (ele && ele.get_attribute("content").to_s.strip) } if title == ''
    (doc/"title:first").each {|ele| title = (ele && ele.inner_text.to_s.strip) } if title == ''
    (doc/"h1:first").each {|ele| title = (ele && ele.inner_text.to_s.strip) } if title == ''
    title
  rescue
    LOGGER.error $!
  end
  def expand_url(found_url)
    long_url, res = self.quick_get(found_url)
    history = res ? [found_url] : []
    while res && long_url != "" && history.length < 3
      long_url, res = self.quick_get(found_url = long_url)
      history << found_url if res
    end
    title = self.get_title_from(res.body) if res && res.body
    result = (title.nil? || title == '') ? long_url : "#{long_url} [#{title}]"
    history.each {|s| UrlCache.create(:short_url => s, :real_url => result)}
    return result
  end
end