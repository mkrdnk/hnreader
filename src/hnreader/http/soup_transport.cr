require "deque"
require "gi-crystal"
require "../constants"
require "./transport"

GICrystal.require("Soup", "3.0")

module HNReader::HTTP
  class SoupRequest < Request
    getter cancellable = Gio::Cancellable.new
    getter? cancelled = false

    def cancel : Nil
      @cancelled = true
      @cancellable.cancel
    end
  end

  class SoupTransport < Transport
    MAX_ACTIVE = 8

    record Job, url : String, request : SoupRequest, callback : Proc(String | Failure, Nil)

    @session = Soup::Session.new(
      max_conns: MAX_ACTIVE,
      max_conns_per_host: MAX_ACTIVE,
      timeout: 20_u32,
      user_agent: "HNReader/#{VERSION}",
    )
    @queue = Deque(Job).new
    @active = 0

    def get(url : String, &callback : String | Failure -> Nil) : Request
      SoupRequest.new.tap do |request|
        @queue << Job.new(url, request, callback)
        pump
      end
    end

    private def pump : Nil
      while @active < MAX_ACTIVE
        break unless job = @queue.shift?
        next if job.request.cancelled?

        start(job)
      end
    end

    private def start(job : Job) : Nil
      unless message = Soup::Message.new("GET", job.url)
        job.callback.call(Failure.new("Invalid request URL."))
        return
      end

      @active += 1
      @session.send_and_read_async(message, 0, job.request.cancellable) do |_, result|
        response = finish(message, result)
        @active -= 1
        job.callback.call(response) unless job.request.cancelled?
        pump
      end
    end

    private def finish(message : Soup::Message, result : Gio::AsyncResult) : String | Failure
      bytes = @session.send_and_read_finish(result)
      if (200...300).includes?(message.status_code)
        String.new(bytes.data || Bytes.empty)
      else
        Failure.new("Server returned HTTP #{message.status_code}.")
      end
    rescue error : GLib::Error
      Failure.new(error.message || "Network request failed.")
    end
  end
end
