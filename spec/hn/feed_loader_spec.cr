require "../spec_helper"
require "../support/fake_transport"
require "../../src/hnreader/hn/feed_loader"

describe HNReader::HN::FeedLoader do
  it "finishes an empty feed and does not request another page" do
    transport = SpecSupport::FakeTransport.new
    changes = 0
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { changes += 1 }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[]")

    loader.items.should be_empty
    loader.loading?.should be_false
    loader.has_more?.should be_false
    loader.error.should be_nil
    changes.should eq(2)

    loader.load_more
    transport.pending.should be_empty
    changes.should eq(2)
  end

  it "preserves feed order and filters unavailable items" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[1,2,3,4,5]")
    transport.reply("item/3.json", SpecSupport.story(3))
    transport.reply("item/5.json", SpecSupport.story(5, ",\"dead\":true"))
    transport.reply("item/4.json", SpecSupport.story(4, ",\"deleted\":true"))
    transport.reply("item/2.json", "null")
    transport.reply("item/1.json", SpecSupport.story(1))
    loader.items.map(&.id).should eq([1, 3])
    loader.loading?.should be_false
    loader.has_more?.should be_false
  end

  it "ignores late responses after switching feeds" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[1]")
    old = transport.pending.first.request
    loader.select_feed(HNReader::HN::Feed::New)
    old.cancelled?.should be_true
    transport.reply("newstories.json", "[2]")
    transport.reply("item/2.json", SpecSupport.story(2))
    transport.reply("item/1.json", SpecSupport.story(1))
    loader.items.map(&.id).should eq([2])
  end

  it "retries a failed batch without losing posts or introducing duplicates" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[1,2,1]")
    transport.reply("item/1.json", SpecSupport.story(1))
    transport.reply("item/2.json", HNReader::Failure.new("Timed out"))
    loader.error.should eq("Timed out")
    loader.items.should be_empty
    loader.load_more
    transport.pending.size.should eq(1) # Successful item is cached.
    transport.reply("item/2.json", SpecSupport.story(2))
    loader.items.map(&.id).should eq([1, 2])
    loader.load_more
    loader.items.map(&.id).should eq([1, 2])
  end

  it "loads 30 posts at a time" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Jobs)
    transport.reply("jobstories.json", (1..31).to_a.to_json)
    transport.pending.size.should eq(30)
    (1..30).each { |id| transport.reply("item/#{id}.json", SpecSupport.story(id)) }
    loader.has_more?.should be_true
    loader.load_more
    transport.reply("item/31.json", SpecSupport.story(31))
    loader.items.size.should eq(31)
    loader.has_more?.should be_false
  end

  it "recovers from malformed feeds and item responses" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "oops")
    loader.error.should_not be_nil
    loader.load_more
    transport.reply("topstories.json", "[1]")
    transport.reply("item/1.json", "{}")
    loader.error.should_not be_nil
    loader.load_more
    transport.reply("item/1.json", SpecSupport.story(1))
    loader.items.size.should eq(1)
  end
end

describe "FeedLoader caching" do
  it "shows a previously opened feed immediately and fetches new data on refresh" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[1]")
    transport.reply("item/1.json", SpecSupport.story(1))
    loader.select_feed(HNReader::HN::Feed::New)
    transport.reply("newstories.json", "[]")

    loader.select_feed(HNReader::HN::Feed::Top)
    loader.items.map(&.id).should eq([1_i64])
    loader.loading?.should be_false
    transport.pending.should be_empty

    loader.select_feed(HNReader::HN::Feed::Top, refresh: true)
    loader.loading?.should be_true
    transport.reply("topstories.json", "[1]")
    transport.reply("item/1.json", SpecSupport.story(1, ",\"score\":42"))
    loader.items.first.score.should eq(42)
    loader.loading?.should be_false
  end
end

describe "Feed update checks" do
  it "counts new IDs without replacing the list, changing pagination or updating the feed cache" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    loader = HNReader::HN::FeedLoader.new(client) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", (1..31).to_a.to_json)
    (1..30).each { |id| transport.reply("item/#{id}.json", SpecSupport.story(id)) }

    loader.check_for_updates
    loader.check_for_updates
    transport.pending.size.should eq(1)
    loader.checking_updates?.should be_true
    transport.reply("topstories.json", "[32,32,31,1,2]")
    loader.new_posts_count.should eq(1)
    loader.checking_updates?.should be_false
    loader.items.map(&.id).should eq((1_i64..30_i64).to_a)
    loader.has_more?.should be_true
    client.feed(HNReader::HN::Feed::Top, HNReader::HTTP::RequestGroup.new) do |result|
      result.should eq((1_i64..31_i64).to_a)
    end
    transport.pending.should be_empty

    loader.check_for_updates
    transport.reply("topstories.json", "[31,2,1]")
    loader.new_posts_count.should eq(0)
  end

  it "keeps the current count and visible content on polling errors, then retries" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.select_feed(HNReader::HN::Feed::Top)
    transport.reply("topstories.json", "[]")
    loader.check_for_updates
    transport.reply("topstories.json", "[1]")
    loader.new_posts_count.should eq(1)
    loader.check_for_updates
    transport.reply("topstories.json", HNReader::Failure.new("Offline"))
    loader.new_posts_count.should eq(1)
    loader.error.should be_nil
    loader.checking_updates?.should be_false
    loader.loading?.should be_false
    loader.check_for_updates
    transport.reply("topstories.json", "[1,2]")
    loader.new_posts_count.should eq(2)
  end

  it "ignores late checks when switching feeds, refreshing or closing" do
    transport = SpecSupport::FakeTransport.new
    loader = HNReader::HN::FeedLoader.new(HNReader::HN::Client.new(transport)) { }
    loader.check_for_updates
    transport.pending.should be_empty
    loader.select_feed(HNReader::HN::Feed::Top)
    loader.check_for_updates
    transport.pending.size.should eq(1)
    transport.reply("topstories.json", "[]")
    loader.check_for_updates
    old = transport.pending.first.request
    loader.select_feed(HNReader::HN::Feed::New)
    old.cancelled?.should be_true
    transport.reply("topstories.json", "[1]")
    transport.reply("newstories.json", "[]")
    loader.new_posts_count.should eq(0)

    loader.check_for_updates
    transport.reply("newstories.json", "[1]")
    loader.new_posts_count.should eq(1)
    loader.check_for_updates
    loader.select_feed(HNReader::HN::Feed::New, refresh: true)
    transport.reply("newstories.json", "[1,2]") # Cancelled check.
    loader.new_posts_count.should eq(0)
    transport.reply("newstories.json", "[]")
    loader.check_for_updates
    loader.cancel
    transport.reply("newstories.json", "[3]")
    loader.new_posts_count.should eq(0)
    loader.check_for_updates
    transport.pending.should be_empty
  end
end
