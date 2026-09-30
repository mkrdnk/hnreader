require "../spec_helper"
require "../support/fake_transport"
require "../../src/hnreader/hn/item_batch"

describe HNReader::HN::ItemBatch do
  it "completes a fully cached batch once and preserves the requested order" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    ids = [2_i64, 1_i64]

    HNReader::HN::ItemBatch.load(client, ids, requests) { }
    transport.reply("item/1.json", SpecSupport.story(1))
    transport.reply("item/2.json", SpecSupport.story(2))

    completions = 0
    HNReader::HN::ItemBatch.load(client, ids, requests) do |result|
      result.as(Array(HNReader::HN::Item)).map(&.id).should eq(ids)
      completions += 1
    end

    completions.should eq(1)
    transport.pending.should be_empty
  end

  it "returns one failure rather than exposing a partially loaded page" do
    transport = SpecSupport::FakeTransport.new
    client = HNReader::HN::Client.new(transport)
    requests = HNReader::HTTP::RequestGroup.new
    completions = 0

    HNReader::HN::ItemBatch.load(client, [1_i64, 2_i64, 3_i64], requests) do |result|
      result.should eq(HNReader::Failure.new("Timed out"))
      completions += 1
    end
    transport.reply("item/2.json", HNReader::Failure.new("Timed out"))
    transport.reply("item/3.json", HNReader::Failure.new("Connection refused"))
    completions.should eq(0)
    transport.reply("item/1.json", SpecSupport.story(1))
    completions.should eq(1)
  end
end
