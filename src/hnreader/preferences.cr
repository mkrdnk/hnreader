require "./hn/feed"

module HNReader
  class Preferences
    getter default_feed : HN::Feed
    getter? reader_mode : Bool

    def self.default_directory : String
      File.join(ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config"), "hnreader")
    end

    def initialize(@path : String = File.join(Preferences.default_directory, "default-feed"),
                   @reader_mode_path : String = File.join(Preferences.default_directory, "reader-mode"))
      @default_feed = read_default_feed
      @reader_mode = read_reader_mode
    end

    def default_feed=(feed : HN::Feed) : HN::Feed
      Dir.mkdir_p(File.dirname(@path))
      File.write("#{@path}.tmp", feed.to_s.downcase)
      File.rename("#{@path}.tmp", @path)
      @default_feed = feed
    end

    def reader_mode=(enabled : Bool) : Bool
      Dir.mkdir_p(File.dirname(@reader_mode_path))
      File.write("#{@reader_mode_path}.tmp", enabled.to_s)
      File.rename("#{@reader_mode_path}.tmp", @reader_mode_path)
      @reader_mode = enabled
    end

    private def read_default_feed : HN::Feed
      HN::Feed.parse?(File.read(@path).strip) || HN::Feed::Top
    rescue File::Error
      HN::Feed::Top
    end

    private def read_reader_mode : Bool
      case File.read(@reader_mode_path).strip
      when "false" then false
      else              true
      end
    rescue File::Error
      true
    end
  end
end
