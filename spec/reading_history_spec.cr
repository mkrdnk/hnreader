require "spec"
require "file_utils"
require "../src/hnreader/reading_history"

private def with_reading_history(& : String ->)
  directory = File.tempname("hnreader-reading")
  Dir.mkdir_p(directory)
  begin
    yield File.join(directory, "reading-history.json")
  ensure
    FileUtils.rm_rf(directory)
  end
end

describe HNReader::ReadingHistory do
  it "persists independent read marks, pages, positions and comment pagination" do
    with_reading_history do |path|
      history = HNReader::ReadingHistory.new(path)
      state = history.story(1_i64)
      history.read?(1_i64).should be_false
      state.read = true
      state.page = "discussion"
      state.reader_mode = false
      state.remember_position("discussion", 420.0)
      state.remember_position("reader:https://example.com/", 750.0)
      state.remember_position("website:https://example.com/", 1200.0)
      state.expand(10_i64, true)
      state.expand(11_i64, true)
      state.remember_loaded(1_i64, 60)
      state.remember_loaded(10_i64, 90)
      history.flush
      state.dirty?.should be_false

      restored = HNReader::ReadingHistory.new(path)
      restored.read?(1_i64).should be_true
      restored.read?(2_i64).should be_false
      progress = restored.story(1_i64)
      progress.page.should eq("discussion")
      progress.reader_mode.should be_false
      progress.position("discussion").should eq(420.0)
      progress.position("reader:https://example.com/").should eq(750.0)
      progress.position("website:https://example.com/").should eq(1200.0)
      progress.expanded?(10_i64).should be_true
      progress.expanded?(11_i64).should be_true
      progress.loaded_count(1_i64).should eq(60)
      progress.loaded_count(10_i64).should eq(90)
      restored.story(2_i64).position("discussion").should eq(0.0)
    end
  end

  it "marks unread without erasing progress and remembers collapsed branches" do
    with_reading_history do |path|
      history = HNReader::ReadingHistory.new(path)
      state = history.story(1_i64)
      state.read = true
      state.remember_position("discussion", 500.0)
      state.expand(10_i64, true)
      history.flush
      state.read = false
      state.expand(10_i64, false)
      history.flush

      restored = HNReader::ReadingHistory.new(path)
      restored.read?(1_i64).should be_false
      restored.story(1_i64).position("discussion").should eq(500.0)
      restored.story(1_i64).expanded?(10_i64).should be_false
    end
  end

  it "does not replace remembered pagination during a partial reload" do
    state = HNReader::ReadingState.new
    state.remember_loaded(1_i64, 90)
    state.remember_loaded(1_i64, 30)
    state.loaded_count(1_i64).should eq(90)
    state.loaded_count(2_i64).should eq(0)
  end

  it "ignores invalid positions and accepts returning to the top" do
    state = HNReader::ReadingState.new
    state.remember_position("discussion", 25.0)
    [-1.0, Float64::NAN, Float64::INFINITY].each do |offset|
      state.remember_position("discussion", offset)
      state.position("discussion").should eq(25.0)
    end
    state.remember_position("discussion", 0.0)
    state.position("discussion").should eq(0.0)
  end

  it "recovers from missing, malformed and incompatible data" do
    with_reading_history do |path|
      HNReader::ReadingHistory.new(path).read?(1_i64).should be_false
      ["not json", %({"1":{"positions":"bad"}})].each do |data|
        File.write(path, data)
        history = HNReader::ReadingHistory.new(path)
        history.read?(1_i64).should be_false
        history.story(2_i64).read = true
        history.flush
        HNReader::ReadingHistory.new(path).read?(2_i64).should be_true
      end
    end
  end

  it "retries failed writes without losing the in-memory state" do
    with_reading_history do |path|
      File.write(path, "not a directory")
      history = HNReader::ReadingHistory.new(File.join(path, "history.json"))
      state = history.story(1_i64)
      state.read = true
      expect_raises(File::Error) { history.flush }
      state.read?.should be_true
      state.dirty?.should be_true
      File.delete(path)
      history.flush
      state.dirty?.should be_false
      HNReader::ReadingHistory.new(File.join(path, "history.json")).read?(1_i64).should be_true
    end
  end

  it "does not write unchanged progress" do
    with_reading_history do |path|
      history = HNReader::ReadingHistory.new(path)
      state = history.story(1_i64)
      state.read = false
      state.page = "article"
      state.remember_position("discussion", 0.0)
      state.expand(10_i64, false)
      history.flush
      File.exists?(path).should be_false
    end
  end
end
