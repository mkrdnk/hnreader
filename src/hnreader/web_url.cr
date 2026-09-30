require "uri"

module HNReader
  module WebURL
    extend self

    def valid?(url : String) : Bool
      uri = URI.parse(url)
      {"http", "https"}.includes?(uri.scheme) && !uri.host.to_s.empty?
    rescue URI::Error
      false
    end
  end
end
