require "../http/request_group"
require "../http/transport"
require "./cache"
require "./feed"
require "./item"

module HNReader::HN
  class Client
    BASE_URL = "https://hacker-news.firebaseio.com/v0"

    @cache_generation = 0_u64

    def initialize(@transport : HTTP::Transport, @base_url : String = BASE_URL, @cache : Cache = Cache.new)
    end

    def clear_cache : Bool
      @cache_generation &+= 1
      @cache.clear
    end

    def feed(feed : Feed, requests : HTTP::RequestGroup, &callback : Array(Int64) | Failure -> Nil) : Nil
      fetch(feed.endpoint, requests, ->parse_feed(String), &callback)
    end

    def item(id : Int64, requests : HTTP::RequestGroup, &callback : Item? | Failure -> Nil) : Nil
      fetch("item/#{id}.json", requests, ->parse_item(String), &callback)
    end

    private def fetch(path : String, requests : HTTP::RequestGroup, decode : String -> T,
                      &callback : T | Failure -> Nil) : Nil forall T
      return if requests.cancelled?

      key = "#{@base_url}/#{path}"
      if body = @cache.read(key)
        cached = decode.call(body)
        unless cached.is_a?(Failure)
          callback.call(cached)
          return
        end
      end

      generation = @cache_generation
      request = @transport.get(key) do |response|
        next if requests.cancelled?

        result = case response
                 in String  then decode.call(response)
                 in Failure then response
                 end
        @cache.write(key, response) if generation == @cache_generation && response.is_a?(String) && !result.is_a?(Failure)
        callback.call(result)
      end
      requests.add(request)
    end

    private def parse_feed(body : String) : Array(Int64) | Failure
      Array(Int64).from_json(body).uniq
    rescue error : JSON::ParseException
      Failure.new("Invalid feed response: #{error.message}")
    end

    private def parse_item(body : String) : Item? | Failure
      Item.parse(body)
    rescue error : JSON::ParseException
      Failure.new("Invalid item response: #{error.message}")
    end
  end
end
