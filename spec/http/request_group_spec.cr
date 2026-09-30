require "../spec_helper"
require "../support/fake_transport"
require "../../src/hnreader/http/request_group"

describe HNReader::HTTP::RequestGroup do
  it "cancels existing requests and requests added after cancellation" do
    requests = HNReader::HTTP::RequestGroup.new
    existing = SpecSupport::FakeRequest.new
    late = SpecSupport::FakeRequest.new
    requests.add(existing)

    requests.cancel
    requests.add(late)

    existing.cancelled?.should be_true
    late.cancelled?.should be_true
  end
end
