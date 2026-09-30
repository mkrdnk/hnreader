require "../failure"
require "./request"

module HNReader::HTTP
  abstract class Transport
    abstract def get(url : String, &callback : String | Failure -> Nil) : Request
  end
end
