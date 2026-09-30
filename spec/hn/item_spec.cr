require "../spec_helper"
require "../../src/hnreader/hn/item"

describe HNReader::HN::Item do
  it "handles null and omitted or nullable fields" do
    HNReader::HN::Item.parse("null").should be_nil
    item = HNReader::HN::Item.parse(%({"id":1,"url":null,"kids":null,"score":null})).not_nil!
    item.kids.should be_empty
    item.url.should be_nil
    item.score.should eq(0)
    item.author.should eq("[deleted]")
  end

  it "preserves replies under deleted comments" do
    item = HNReader::HN::Item.parse(%({"id":2,"deleted":true,"kids":[3,4]})).not_nil!
    item.deleted?.should be_true
    item.kids.should eq([3_i64, 4_i64])
  end

  it "maps API fields, normalizes text and ignores unknown fields" do
    item = HNReader::HN::Item.parse(%({
      "id": 3, "by": "reader", "title": "GTK &amp; Crystal", "url": "",
      "future_field": {"enabled": true}
    })).not_nil!

    item.author.should eq("reader")
    item.title.should eq("GTK & Crystal")
    item.url.should be_nil
    item.visible?.should be_true
  end

  it "uses defaults for null optional fields" do
    item = HNReader::HN::Item.parse(%({
      "id": 4, "type": null, "title": null, "text": null, "by": null,
      "time": null, "descendants": null, "deleted": null, "dead": null
    })).not_nil!

    item.type.should eq("story")
    item.title.should eq("Untitled")
    item.author.should eq("[deleted]")
    item.text.should be_empty
    item.time.should eq(0)
    item.descendants.should eq(0)
    item.visible?.should be_true
  end

  it "rejects malformed typed fields instead of silently discarding them" do
    expect_raises(JSON::ParseException) do
      HNReader::HN::Item.parse(%({"id": 5, "score": "many"}))
    end
  end
end
