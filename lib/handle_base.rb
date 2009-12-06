module Rack
  class HandleBase
    def initialize app
      @app = app
    end

    def call(env)
      status, headers, body = self.handle_request(env) || @app.call(env)
      return self.handle_response(status, headers, body) || [status, headers, body]
    end

    # subclass overwrite
    def handle_request(env)
      nil # otherwise, return [status, headers, body]
    end
    def handle_response(status, headers, body)
      nil # otherwise, return [status, headers, body]
    end
  end
end