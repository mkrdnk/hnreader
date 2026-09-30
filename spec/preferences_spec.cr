require "spec"
require "file_utils"
require "../src/hnreader/preferences"

private def with_preferences_path(& : String ->)
  directory = File.tempname("hnreader-preferences")
  Dir.mkdir_p(directory)
  begin
    yield File.join(directory, "default-feed")
  ensure
    FileUtils.rm_rf(directory)
  end
end

describe HNReader::Preferences do
  it "uses Top for missing or invalid preferences" do
    with_preferences_path do |path|
      HNReader::Preferences.new(path).default_feed.should eq(HNReader::HN::Feed::Top)
      File.write(path, "unknown")
      HNReader::Preferences.new(path).default_feed.should eq(HNReader::HN::Feed::Top)
    end
  end

  it "restores each saved feed on the next launch" do
    with_preferences_path do |path|
      preferences = HNReader::Preferences.new(path)
      HNReader::HN::Feed.each do |feed|
        preferences.default_feed = feed
        HNReader::Preferences.new(path).default_feed.should eq(feed)
      end
    end
  end

  it "keeps the previous preference if saving fails" do
    with_preferences_path do |path|
      preferences = HNReader::Preferences.new(File.join(path, "feed"))
      File.write(path, "not a directory")
      expect_raises(File::Error) { preferences.default_feed = HNReader::HN::Feed::New }
      preferences.default_feed.should eq(HNReader::HN::Feed::Top)
    end
  end
end
