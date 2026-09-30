module HNReader::HTTP
  abstract class Request
    abstract def cancel : Nil
  end
end
