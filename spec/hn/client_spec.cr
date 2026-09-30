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
