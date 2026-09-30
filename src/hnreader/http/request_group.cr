require "./request"

module HNReader::HTTP
  class RequestGroup
    getter? cancelled = false

    @requests = [] of Request

    def add(request : Request) : Nil
      if @cancelled
        request.cancel
      else
        @requests << request
      end
    end

    def cancel : Nil
      @cancelled = true
      @requests.each(&.cancel)
      @requests.clear
    end
  end
end
