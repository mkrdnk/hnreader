require "uri"
require "../hn/item"

module HNReader::UI
  module Formatting
    extend self

    def domain(url : String) : String
      URI.parse(url).host || url
    rescue URI::Error
      url
    end

    def age(timestamp : Int64) : String
      return "" if timestamp == 0

      seconds = Math.max(0_i64, Time.utc.to_unix - timestamp)
      return "just now" if seconds < 60
      return "#{seconds // 60}m ago" if seconds < 3600
      return "#{seconds // 3600}h ago" if seconds < 86400

      "#{seconds // 86400}d ago"
    end

    def metadata(item : HN::Item) : String
      "#{item.score} points · #{item.author} · #{age(item.time)} · #{item.descendants} comments"
    end
  end
end
