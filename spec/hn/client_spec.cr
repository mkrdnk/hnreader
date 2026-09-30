require "../spec_helper"
require "../support/fake_transport"
require "../../src/hnreader/hn/client"

describe HNReader::HN::Client do
  it "returns a typed failure for invalid item data" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    completed = false

    client.item(1_i64, requests) do |result|
      result.should be_a(HNReader::Failure)
      completed = true
    end
    transport.reply("item/1.json", %({"id":1,"score":"invalid"}))

    completed.should be_true
  end

  it "does not disguise a callback bug as a parsing error" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    client.item(1_i64, requests) { raise ArgumentError.new("callback bug") }

    expect_raises(ArgumentError, "callback bug") do
      transport.reply("item/1.json", SpecSupport.story(1))
    end
  end

  it "preserves network errors without treating them as JSON failures" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    received_error = nil.as(String?)

    client.item(1_i64, requests) do |result|
      received_error = result.as(HNReader::Failure).message
    end
    transport.reply("item/1.json", HNReader::Failure.new("Connection refused"))

    received_error.should eq("Connection refused")
  end

  it "does not dispatch requests for a cancelled screen" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    requests.cancel

    client.feed(HNReader::HN::Feed::Top, requests) { fail "Unexpected feed callback" }
    client.item(1_i64, requests) { fail "Unexpected item callback" }

    transport.pending.should be_empty
  end

  it "returns null items without inventing a network error" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    completed = false

    client.item(1_i64, requests) do |result|
      result.should be_nil
      completed = true
    end
    transport.reply("item/1.json", "null")

    completed.should be_true
  end
end

describe "Client caching" do
  it "reuses feeds and items across clients and refreshes after clearing the cache" do
    cache = HNReader::HN::Cache.new
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport, cache: cache)
    requests = HNReader::HTTP::RequestGroup.new
    client.feed(HNReader::HN::Feed::Top, requests) { }
    transport.reply("topstories.json", "[1]")
    client.item(1_i64, requests) { }
    transport.reply("item/1.json", %({"id":1,"title":"&amp;lt;"}))

    restored = HNReader::HN::Client.new(transport, cache: cache)
    ids = [] of Int64
    title = ""
    restored.feed(HNReader::HN::Feed::Top, requests) { |result| ids = result.as(Array(Int64)) }
    restored.item(1_i64, requests) { |result| title = result.as(HNReader::HN::Item).title }
    ids.should eq([1_i64])
    title.should eq("&lt;")
    transport.pending.should be_empty

    restored.clear_cache
    restored.feed(HNReader::HN::Feed::Top, requests) { }
    restored.item(1_i64, requests) { }
    transport.pending.size.should eq(2)
  end

  it "reloads expired feeds and items" do
    now = Time.utc
    cache = HNReader::HN::Cache.new(clock: -> { now })
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport, cache: cache)
    requests = HNReader::HTTP::RequestGroup.new
    client.feed(HNReader::HN::Feed::Top, requests) { }
    transport.reply("topstories.json", "[1]")
    client.item(1_i64, requests) { }
    transport.reply("item/1.json", SpecSupport.story(1))
    now += 5.minutes
    client.feed(HNReader::HN::Feed::Top, requests) { }
    client.item(1_i64, requests) { }
    transport.pending.size.should eq(2)
  end

  it "fetches fresh data when a cached response is malformed" do
    cache = HNReader::HN::Cache.new
    cache.write("#{HNReader::HN::Client::BASE_URL}/topstories.json", "invalid")
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport, cache: cache)
    received = [] of Int64
    client.feed(HNReader::HN::Feed::Top, HNReader::HTTP::RequestGroup.new) do |result|
      received = result.as(Array(Int64))
    end
    transport.reply("topstories.json", "[2]")
    received.should eq([2_i64])
  end

  it "keeps responses from different API servers separate" do
    cache = HNReader::HN::Cache.new
    transport = SpecSupport::FakeTransport.new
    requests = HNReader::HTTP::RequestGroup.new
    HNReader::HN::Client.new(transport, "https://one.test", cache).item(1_i64, requests) { }
    transport.reply("item/1.json", SpecSupport.story(1))
    HNReader::HN::Client.new(transport, "https://two.test", cache).item(1_i64, requests) { }
    transport.pending.size.should eq(1)
  end
end

describe "Clearing the cache during a request" do
  it "delivers pending responses without putting them back into the cleared cache" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    received = false
    client.item(1_i64, requests) { |result| received = result.is_a?(HNReader::HN::Item) }
    client.clear_cache.should be_true
    transport.reply("item/1.json", SpecSupport.story(1))
    received.should be_true
    client.item(1_i64, requests) { }
    transport.pending.size.should eq(1)
    transport.reply("item/1.json", SpecSupport.story(1))
    client.item(1_i64, requests) { }
    transport.pending.should be_empty
  end
end
