module HNReader
  # A failed request is distinct from a successful response containing no item.
  record Failure, message : String
end
