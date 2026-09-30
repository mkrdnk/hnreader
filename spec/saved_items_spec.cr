require "spec"
require "file_utils"
require "../src/hnreader/saved_items"

private def with_saved_items_path(& : String ->)
  directory = File.tempname("hnreader-saved-items")
  Dir.mkdir_p(directory)
  begin
    yield File.join(directory, "saved-items.json")
  ensure
    FileUtils.rm_rf(directory)
  end
end

private def saved_item(id : Int64) : HNReader::HN::Item
  HNReader::HN::Item.from_json(%({"id":#{id}}))
end

describe HNReader::SavedItems do
  it "persists saved item ids between launches" do
    with_saved_items_path do |path|
      story = saved_item(1_i64)
      comment = saved_item(2_i64)
      saved = HNReader::SavedItems.new(path)

      saved.toggle(story).should be_true
      saved.toggle(comment).should be_true
      saved.ids.should eq([2_i64, 1_i64])

      restored = HNReader::SavedItems.new(path)
      restored.saved?(story).should be_true
      restored.saved?(comment).should be_true
      restored.ids.should eq([2_i64, 1_i64])
    end
  end

  it "removes an item when it is toggled again" do
    with_saved_items_path do |path|
      item = saved_item(1_i64)
      saved = HNReader::SavedItems.new(path)

      saved.toggle(item).should be_true
      saved.toggle(item).should be_false
      saved.ids.should be_empty
      HNReader::SavedItems.new(path).saved?(item).should be_false
    end
  end

  it "recovers from invalid saved data" do
    with_saved_items_path do |path|
      File.write(path, "not json")
      item = saved_item(1_i64)
      saved = HNReader::SavedItems.new(path)

      saved.saved?(item).should be_false
      saved.toggle(item).should be_true
      HNReader::SavedItems.new(path).saved?(item).should be_true
    end
  end

  it "keeps its previous state if saving fails" do
    with_saved_items_path do |path|
      saved = HNReader::SavedItems.new(File.join(path, "saved-items.json"))
      item = saved_item(1_i64)
      File.write(path, "not a directory")

      expect_raises(File::Error) { saved.toggle(item) }
      saved.saved?(item).should be_false
    end
  end
end
