module Rack
  class HandleBase
    def initialize app
      @app = app
    end
    def call(env)
      response = self.handle_request(env)    || @app.call(env)
      return self.handle_response(*response) || response
    end

    # subclass overwrite
    def handle_request(env)
      nil # otherwise, return [status, headers, body]
    end
    def handle_response(status, headers, body)
      LOGGER.debug "No reaction to Content-Type = #{headers['Content-Type'].inspect}"
      nil # otherwise, return [status, headers, body]
    end
  end
end