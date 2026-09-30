require "./hn/feed"

module HNReader
  class Preferences
    getter default_feed : HN::Feed

    def initialize(@path : String = File.join(ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config"), "hnreader", "default-feed"))
      @default_feed = read
    end

    def default_feed=(feed : HN::Feed) : HN::Feed
      Dir.mkdir_p(File.dirname(@path))
      File.write("#{@path}.tmp", feed.to_s.downcase)
      File.rename("#{@path}.tmp", @path)
      @default_feed = feed
    end

    private def read : HN::Feed
      HN::Feed.parse?(File.read(@path).strip) || HN::Feed::Top
    rescue File::Error
      HN::Feed::Top
    end
  end
end
