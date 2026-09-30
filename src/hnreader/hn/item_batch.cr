require "./client"

module HNReader::HN
  # Batches preserve the API's order even when requests complete out of order.
  class ItemBatch
    def self.load(client : Client, ids : Array(Int64), requests : HTTP::RequestGroup,
                  &callback : Array(Item) | Failure -> Nil) : Nil
      return if requests.cancelled?

      if ids.empty?
        callback.call([] of Item)
        return
      end

      items = Array(Item?).new(ids.size, nil)
      remaining = ids.size
      failure = nil.as(Failure?)
      ids.each_with_index do |id, index|
        client.item(id, requests) do |result|
          case result
          in Failure then failure ||= result
          in Item?   then items[index] = result
          end
          remaining -= 1
          next unless remaining.zero? && !requests.cancelled?

          if error = failure
            callback.call(error)
          else
            callback.call(items.compact)
          end
        end
      end
    end
  end
end
