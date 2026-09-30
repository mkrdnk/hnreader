require "../hn/item_batch"
require "../saved_items"
require "../constants"
require "./formatting"
require "./widgets"

module HNReader::UI
  class SavedView
    PAGE_SIZE = 30

    getter widget = Gtk::ScrolledWindow.new(hscrollbar_policy: Gtk::PolicyType::Never)

    @list = Gtk::ListBox.new(selection_mode: Gtk::SelectionMode::None, css_classes: ["boxed-list"])
    @status = Gtk::Label.new(wrap: true)
    @spinner = Gtk::Spinner.new(halign: Gtk::Align::Center)
    @more_button : Gtk::Button
    @requests = HTTP::RequestGroup.new
    @ids = [] of Int64
    @items = [] of HN::Item
    @offset = 0
    @loading = false

    def initialize(@client : HN::Client, @saved : SavedItems,
                   @on_selected : HN::Item -> Nil, @open_link : String -> Nil)
      @more_button = Widgets.button("Load More") { load_more }
      @list.row_activated_signal.connect do |row|
        if item = @items[row.index]?
          comment?(item) ? open_comment(item) : @on_selected.call(item)
        end
      end
      build
    end

    def show : Nil
      close
      @requests = HTTP::RequestGroup.new
      @ids = @saved.ids
      @items.clear
      @offset = 0
      @loading = false
      Widgets.clear(@list)
      update_status
      load_more unless @ids.empty?
    end

    def close : Nil
      @requests.cancel
      @loading = false
    end

    private def build : Nil
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 18)
      Widgets.margins(content)
      content.append(Widgets.label("Saved items", "title-1"))
      content.append(Widgets.label("Articles and comments you bookmarked.", "dim-label"))
      @more_button.halign = Gtk::Align::Center
      {@list, @spinner, @status, @more_button}.each { |child| content.append(child) }
      @widget.child = Adw::Clamp.new(maximum_size: 900, child: content)
    end

    private def load_more : Nil
      return if @loading || @requests.cancelled?

      @loading = true
      update_status
      ids = @ids[@offset, PAGE_SIZE]
      HN::ItemBatch.load(@client, ids, @requests) do |result|
        @loading = false
        case result
        in Failure
          update_status
          @status.label = result.message
          @status.visible = true
          @more_button.label = "Retry"
          @more_button.visible = true
        in Array(HN::Item)
          result.each { |item| append(item) }
          @offset += ids.size
          @more_button.label = "Load More"
          update_status
        end
      end
    end

    private def append(item : HN::Item) : Nil
      row = Gtk::ListBoxRow.new
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 7)
      Widgets.margins(content, 16)

      heading = Gtk::Box.new(Gtk::Orientation::Horizontal, 8)
      if comment?(item)
        heading.append(Widgets.label("Comment by #{item.author}", "heading"))
        heading.append(Widgets.icon_button("go-jump-symbolic", "Open comment on Hacker News") do
          open_comment(item)
        end)
      else
        heading.append(Widgets.label(item.title, "heading"))
      end
      heading.append(Widgets.save_button(true, comment?(item) ? "comment" : "article") do
        remove(item, row)
        false
      end)
      content.append(heading)

      if comment?(item)
        content.append(Widgets.label(Formatting.age(item.time), "dim-label"))
        if item.visible?
          content.append(Widgets.rich_text(item.text, &@open_link))
        else
          content.append(Widgets.label(item.deleted? ? "[deleted]" : "[unavailable]", "dim-label"))
        end
      else
        if url = item.url
          content.append(Widgets.label(Formatting.domain(url), "caption"))
        end
        content.append(Widgets.label(Formatting.metadata(item), "dim-label"))
      end

      row.child = content
      @items << item
      @list.append(row)
    end

    private def remove(item : HN::Item, row : Gtk::ListBoxRow) : Nil
      @saved.toggle(item)
      index = row.index
      @items.delete_at(index) if index >= 0
      @list.remove(row)
      update_status
    end

    private def update_status : Nil
      @spinner.spinning = @loading
      @spinner.visible = @loading
      @status.label = "No saved items yet."
      @status.visible = !@loading && @list.first_child.nil? && @offset >= @ids.size
      @more_button.visible = !@loading && @offset < @ids.size
      @more_button.sensitive = !@loading
    end

    private def open_comment(item : HN::Item) : Nil
      @open_link.call("#{HN_ITEM_URL}#{item.id}")
    end

    private def comment?(item : HN::Item) : Bool
      item.type == "comment"
    end
  end
end
