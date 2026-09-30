require "./item_batch"

module HNReader::HN
  class FeedLoader
    PAGE_SIZE = 30

    getter feed = Feed::Top
    getter items = [] of Item
    getter? loading = false
    getter error : String?
    getter new_posts_count = 0
    getter? checking_updates = false

    @ids : Array(Int64)?
    @offset = 0
    @update_requests = HTTP::RequestGroup.new
    @requests = HTTP::RequestGroup.new

    def initialize(@client : Client, &@changed : -> Nil)
    end

    def has_more? : Bool
      @ids.try { |ids| @offset < ids.size } || false
    end

    def select_feed(@feed : Feed, refresh : Bool = false) : Nil
      cancel_update_check
      @new_posts_count = 0
      @requests.cancel
      @requests = HTTP::RequestGroup.new
      @client.clear_cache if refresh
      @items.clear
      @ids = nil
      @offset = 0
      begin_loading

      @client.feed(feed, @requests) do |result|
        @loading = false
        case result
        in Failure
          @error = result.message
          @changed.call
        in Array(Int64)
          @ids = result
          if result.empty?
            @changed.call
          else
            load_more
          end
        end
      end
    end

    def load_more : Nil
      return if loading?

      unless ids = @ids
        select_feed(@feed)
        return
      end
      return unless has_more?

      page = ids[@offset, PAGE_SIZE]
      begin_loading
      ItemBatch.load(@client, page, @requests) do |result|
        @loading = false
        case result
        in Failure
          @error = result.message
        in Array(Item)
          @items.concat(result.select(&.visible?)).uniq!(&.id)
          @offset += page.size
        end
        @changed.call
      end
    end

    # Compare against the entire feed, including pages not yet loaded. Ranking
    # changes alone are not new posts, and checks never change the visible list.
    def check_for_updates : Nil
      return if loading? || checking_updates? || @requests.cancelled?
      return unless ids = @ids

      @update_requests.cancel
      requests = @update_requests = HTTP::RequestGroup.new
      @checking_updates = true
      @client.feed(@feed, requests, use_cache: false) do |result|
        next if requests.cancelled?
        @checking_updates = false
        if result.is_a?(Array(Int64))
          @new_posts_count = (result - ids).size
          @changed.call
        end
      end
    end

    def cancel : Nil
      @requests.cancel
      cancel_update_check
    end

    private def cancel_update_check : Nil
      @update_requests.cancel
      @checking_updates = false
    end

    private def begin_loading : Nil
      @loading = true
      @error = nil
      @changed.call
    end
  end
end
