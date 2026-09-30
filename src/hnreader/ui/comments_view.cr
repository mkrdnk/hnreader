require "../hn/item_batch"
require "./formatting"
require "./widgets"

module HNReader::UI
  # Each level has its own pagination. Replies aren't requested until expanded.
  class CommentsView
    PAGE_SIZE = 30

    getter widget = Gtk::Box.new(Gtk::Orientation::Vertical, 12)

    @rows = Gtk::Box.new(Gtk::Orientation::Vertical, 12)
    @status = Gtk::Label.new(wrap: true, css_classes: ["dim-label"])
    @more : Gtk::Button
    @offset = 0
    @loading = false
    @loaded = false
    @children = [] of CommentsView

    def initialize(@client : HN::Client, @ids : Array(Int64), @requests : HTTP::RequestGroup,
                   @depth : Int32, &@open_link : String -> Nil)
      @more = Widgets.button("Load More") { load_more }
      @more.halign = Gtk::Align::Center
      {@rows, @status, @more}.each { |child| @widget.append(child) }
      @more.visible = false
    end

    def load : Nil
      load_more unless @loaded || @loading
    end

    private def load_more : Nil
      return if @loading || @requests.cancelled?

      @loading = true
      @status.label = "Loading comments…"
      @status.visible = true
      @more.sensitive = false
      ids = @ids[@offset, PAGE_SIZE]
      HN::ItemBatch.load(@client, ids, @requests) do |result|
        @loading = false
        @more.sensitive = true
        case result
        in Failure
          @status.label = result.message
          @more.label = "Retry"
          @more.visible = true
        in Array(HN::Item)
          @loaded = true
          result.each { |item| append(item) }
          @offset += ids.size
          @status.label = "No comments yet."
          @status.visible = @offset == 0
          @more.label = "Load More"
          @more.visible = @offset < @ids.size
        end
      end
    end

    private def append(item : HN::Item) : Nil
      box = Gtk::Box.new(Gtk::Orientation::Vertical, 8)
      if @depth == 0
        Widgets.margins(box, 12)
      else
        box.margin_top = 8
        box.append(Gtk::Separator.new(Gtk::Orientation::Horizontal))
      end
      meta = Widgets.label("#{item.author} · #{Formatting.age(item.time)}", "caption")
      meta.add_css_class("dim-label")
      box.append(meta)
      unless item.visible?
        box.append(Widgets.label(item.deleted? ? "[deleted]" : "[unavailable]", "dim-label"))
      else
        box.append(Widgets.rich_text(item.text, &@open_link))
      end
      unless item.kids.empty?
        label = item.kids.size == 1 ? "1 reply" : "#{item.kids.size} replies"
        expander = Gtk::Expander.new(label)
        child = CommentsView.new(@client, item.kids, @requests, @depth + 1, &@open_link)
        # Keep deeper threads readable instead of narrowing without limit.
        child.widget.margin_start = @depth < 3 ? 12 : 0
        expander.child = child.widget
        expander.notify_signal["expanded"].connect do
          child.load if expander.expanded
        end
        @children << child
        box.append(expander)
      end
      if @depth == 0
        card = Gtk::Box.new(orientation: Gtk::Orientation::Vertical, css_classes: ["card"])
        card.append(box)
        @rows.append(card)
      else
        @rows.append(box)
      end
    end
  end
end
