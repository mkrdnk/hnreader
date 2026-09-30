require "../spec_helper"
require "file_utils"
require "../../src/hnreader/hn/cache"

private def with_cache_directory(& : String ->)
  directory = File.tempname("hnreader-cache")
  begin
    yield directory
  ensure
    FileUtils.rm_rf(directory)
  end
end

describe HNReader::HN::Cache do
  it "persists responses across instances and expires them without extending their lifetime on reads" do
    with_cache_directory do |directory|
      now = Time.utc
      clock = -> { now }
      cache = HNReader::HN::Cache.new(directory, clock)
      cache.write("https://example.com/item/1.json", "response")
      restored = HNReader::HN::Cache.new(directory, clock)
      now += 4.minutes
      restored.read("https://example.com/item/1.json").should eq("response")
      now += 1.minute
      restored.read("https://example.com/item/1.json").should be_nil
      HNReader::HN::Cache.new(directory, clock).read("https://example.com/item/1.json").should be_nil
      Dir.glob(File.join(directory, "*.json")).should be_empty
    end
  end

  it "clears memory and disk while preserving unrelated files" do
    with_cache_directory do |directory|
      cache = HNReader::HN::Cache.new(directory)
      cache.write("feed", "[]")
      File.write(File.join(directory, "keep.txt"), "keep")
      cache.clear.should be_true
      cache.read("feed").should be_nil
      HNReader::HN::Cache.new(directory).read("feed").should be_nil
      File.read(File.join(directory, "keep.txt")).should eq("keep")
      cache.write("feed", "[1]")
      cache.read("feed").should eq("[1]")
      HNReader::HN::Cache.new(directory).read("feed").should eq("[1]")
    end
  end

  it "continues caching in memory when disk storage is unavailable" do
    with_cache_directory do |directory|
      File.write(directory, "not a directory")
      cache = HNReader::HN::Cache.new(directory)
      cache.read("feed").should be_nil
      cache.write("feed", "[]")
      cache.read("feed").should eq("[]")
      cache.clear
      cache.read("feed").should be_nil
    end
  end
end

describe "Cache clear failures" do
  it "reports failed disk removal while still clearing memory" do
    with_cache_directory do |directory|
      cache = HNReader::HN::Cache.new(directory)
      cache.write("feed", "[]")
      Dir.mkdir(File.join(directory, "blocked.json"))
      cache.clear.should be_false
      cache.read("feed").should be_nil
      HNReader::HN::Cache.new(directory).read("feed").should be_nil
    end
  end
end
