require "../../src/hnreader/http/transport"

module SpecSupport
  class FakeRequest < HNReader::HTTP::Request
    getter? cancelled = false

    def cancel : Nil
      @cancelled = true
    end
  end

  class FakeTransport < HNReader::HTTP::Transport
    record Pending, url : String, request : FakeRequest, callback : Proc(String | HNReader::Failure, Nil)
    getter pending = [] of Pending

    def get(url : String, &callback : String | HNReader::Failure -> Nil) : HNReader::HTTP::Request
      request = FakeRequest.new
      @pending << Pending.new(url, request, callback)
      request
    end

    # Deliberately deliver even cancelled requests to test stale-response protection.
    def reply(suffix : String, response : String | HNReader::Failure) : Nil
      index = @pending.index { |p| p.url.ends_with?(suffix) }.not_nil!
      @pending.delete_at(index).callback.call(response)
    end
  end

  def self.story(id : Int32, extra = "") : String
    %({"id":#{id},"title":"Story #{id}"#{extra}})
  end
end
