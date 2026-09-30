require "../http/request_group"
require "../http/transport"
require "./feed"
require "./item"

module HNReader::HN
  class Client
    BASE_URL = "https://hacker-news.firebaseio.com/v0"

    @cache = {} of Int64 => Item

    def initialize(@transport : HTTP::Transport, @base_url : String = BASE_URL)
    end

    def clear_cache : Nil
      @cache.clear
    end

    def feed(feed : Feed, requests : HTTP::RequestGroup, &callback : Array(Int64) | Failure -> Nil) : Nil
      fetch(feed.endpoint, requests, ->parse_feed(String), &callback)
    end

    def item(id : Int64, requests : HTTP::RequestGroup, &callback : Item? | Failure -> Nil) : Nil
      return if requests.cancelled?

      if cached = @cache[id]?
        callback.call(cached)
        return
      end

      fetch("item/#{id}.json", requests, ->parse_item(String)) do |result|
        @cache[id] = result if result.is_a?(Item)
        callback.call(result)
      end
    end

    private def fetch(path : String, requests : HTTP::RequestGroup, decode : String -> T,
                      &callback : T | Failure -> Nil) : Nil forall T
      return if requests.cancelled?

      request = @transport.get("#{@base_url}/#{path}") do |response|
        next if requests.cancelled?

        result = case response
                 in String  then decode.call(response)
                 in Failure then response
                 end
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
