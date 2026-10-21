require "json"

module HNReader
  # Reading progress is user data, not an expiring API cache.
  class ReadingState
    include JSON::Serializable

    getter? read = false
    getter page = "article"
    getter reader_mode : Bool? = nil
    @positions = {} of String => Float64
    @expanded = [] of Int64
    @loaded = {} of Int64 => Int32
    @[JSON::Field(ignore: true)]
    property? dirty = false

    def initialize
    end

    def read=(value : Bool) : Bool
      @dirty ||= @read != value
      @read = value
    end

    def page=(value : String) : String
      @dirty ||= @page != value
      @page = value
    end

    def reader_mode=(value : Bool) : Bool
      @dirty ||= @reader_mode != value
      @reader_mode = value
    end

    def position(key : String) : Float64
      value = @positions[key]? || 0.0
      value.finite? && value >= 0 ? value : 0.0
    end

    def remember_position(key : String, value : Float64) : Nil
      return unless value.finite? && value >= 0
      return if position(key) == value

      @positions[key] = value
      @dirty = true
    end

    def website_positions : Hash(String, Float64)
      @positions.select { |key, _| key.starts_with?("website:") }
    end

    def expanded?(id : Int64) : Bool
      @expanded.includes?(id)
    end

    def expand(id : Int64, expanded : Bool) : Nil
      return if expanded?(id) == expanded

      expanded ? @expanded << id : @expanded.delete(id)
      @dirty = true
    end

    def loaded_count(parent : Int64) : Int32
      Math.max(0, @loaded[parent]? || 0)
    end

    def remember_loaded(parent : Int64, count : Int32) : Nil
      return if count <= loaded_count(parent)

      @loaded[parent] = count
      @dirty = true
    end
  end

  class ReadingHistory
    @stories : Hash(Int64, ReadingState)

    def self.default_path : String
      data_home = ENV["XDG_DATA_HOME"]?.try(&.presence) || File.join(Path.home.to_s, ".local", "share")
      File.join(data_home, "hnreader", "reading-history.json")
    end

    def initialize(@path : String = ReadingHistory.default_path)
      @stories = read
    end

    def story(id : Int64) : ReadingState
      @stories[id] ||= ReadingState.new
    end

    def read?(id : Int64) : Bool
      @stories[id]?.try(&.read?) || false
    end

    # The window coalesces scroll updates and flushes again on navigation/close.
    # Failed writes leave dirty state intact so the next flush can retry.
    def flush : Nil
      return unless @stories.any? { |_, state| state.dirty? }

      directory = File.dirname(@path)
      Dir.mkdir_p(directory)
      File.tempfile("reading-history-", ".tmp", dir: directory) do |file|
        @stories.to_json(file)
        file.close
        File.rename(file.path, @path)
      ensure
        File.delete?(file.path)
      end
      @stories.each_value { |state| state.dirty = false }
    end

    private def read : Hash(Int64, ReadingState)
      Hash(Int64, ReadingState).from_json(File.read(@path))
    rescue File::Error | JSON::ParseException
      {} of Int64 => ReadingState
    end
  end
end
