require "json"
require "./hn/item"

module HNReader
  class SavedItems
    @ids : Array(Int64)

    def self.default_path : String
      data_home = ENV["XDG_DATA_HOME"]?.try(&.presence) || File.join(Path.home.to_s, ".local", "share")
      File.join(data_home, "hnreader", "saved-items.json")
    end

    def initialize(@path : String = SavedItems.default_path)
      @ids = read
    end

    def ids : Array(Int64)
      @ids.dup
    end

    def saved?(item : HN::Item) : Bool
      @ids.includes?(item.id)
    end

    def toggle(item : HN::Item) : Bool
      ids = @ids.dup
      saved = !ids.includes?(item.id)
      if saved
        ids.unshift(item.id)
      else
        ids.delete(item.id)
      end
      write(ids)
      @ids = ids
      saved
    end

    private def read : Array(Int64)
      Array(Int64).from_json(File.read(@path)).uniq
    rescue File::Error | JSON::ParseException
      [] of Int64
    end

    private def write(ids : Array(Int64)) : Nil
      directory = File.dirname(@path)
      Dir.mkdir_p(directory)
      File.tempfile("saved-items-", ".tmp", dir: directory) do |file|
        ids.to_json(file)
        file.close
        File.rename(file.path, @path)
      ensure
        File.delete?(file.path)
      end
    end
  end
end
