module HNReader::HN
  class Cache
    TTL = 5.minutes

    record Entry, body : String, saved_at : Time
    @entries = {} of String => Entry
    @read_disk = true

    def self.default_directory : String
      File.join(ENV["XDG_CACHE_HOME"]?.try(&.presence) || File.join(Path.home.to_s, ".cache"), "hnreader", "api-v1")
    end

    def initialize(@directory : String? = nil, @clock : Proc(Time) = -> { Time.utc })
      prune_disk
    end

    def read(key : String) : String?
      if entry = @entries[key]?
        return entry.body if fresh?(entry.saved_at)
        @entries.delete(key)
      end
      return unless @read_disk
      return unless path = path_for(key)

      saved_at = File.info(path).modification_time
      return unless fresh?(saved_at)
      body = File.read(path)
      @entries[key] = Entry.new(body, saved_at)
      body
    rescue IO::Error
      nil
    end

    def write(key : String, body : String) : Nil
      @entries.reject! { |_, entry| !fresh?(entry.saved_at) }
      @entries[key] = Entry.new(body, @clock.call)
      return unless path = path_for(key)

      directory = File.dirname(path)
      Dir.mkdir_p(directory)
      File.tempfile("response-", ".tmp", dir: directory) do |file|
        file.print(body)
        file.close
        File.touch(file.path, @entries[key].saved_at)
        File.rename(file.path, path)
      ensure
        File.delete?(file.path)
      end
    rescue IO::Error
    end

    def clear : Bool
      @entries.clear
      # Also bypass files that could not be removed.
      @read_disk = false
      each_file { |path| File.delete(path) }
    end

    private def fresh?(saved_at : Time) : Bool
      age = @clock.call - saved_at
      age >= Time::Span.zero && age < TTL
    end

    private def path_for(key : String) : String?
      @directory.try { |directory| File.join(directory, "#{key.to_slice.hexstring}.json") }
    end

    private def prune_disk : Nil
      each_file do |path|
        File.delete(path) unless fresh?(File.info(path).modification_time)
      end
    end

    private def each_file(& : String ->) : Bool
      return true unless directory = @directory
      success = true
      Dir.glob(File.join(directory, "*.json")) do |path|
        begin
          yield path
        rescue IO::Error
          success = false
        end
      end
      success
    rescue IO::Error
      false
    end
  end
end
