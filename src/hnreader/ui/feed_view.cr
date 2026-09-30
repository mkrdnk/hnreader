require "../hn/feed_loader"
require "./formatting"
require "./widgets"

module HNReader::UI
  class FeedView
    getter widget = Gtk::ScrolledWindow.new(hscrollbar_policy: Gtk::PolicyType::Never)
    getter selector : Gtk::DropDown
    getter refresh_button : Gtk::Button
    getter updates_banner = Adw::Banner.new(title: "New posts available", button_label: "Show", revealed: false)

    @loader : HN::FeedLoader
    @list = Gtk::ListBox.new(selection_mode: Gtk::SelectionMode::None, css_classes: ["boxed-list"])
    @status = Gtk::Label.new(wrap: true)
    @spinner = Gtk::Spinner.new(halign: Gtk::Align::Center)
    @more_button : Gtk::Button
    @rendered_ids = [] of Int64
    @scroll_position = 0.0
    @closed = false
    @check_after_load = true
    @update_timer : UInt32?

    def initialize(client : HN::Client, initial_feed : HN::Feed = HN::Feed::Top, &on_selected : HN::Item -> Nil)
      @loader = HN::FeedLoader.new(client) { update }
      @more_button = Widgets.button("Load More") { @loader.load_more }
      @refresh_button = Widgets.icon_button("view-refresh-symbolic", "Refresh feed") do
        @loader.select_feed(@loader.feed, refresh: true)
      end
      @updates_banner.button_clicked_signal.connect do
        @scroll_position = 0.0
        @widget.vadjustment.value = 0.0
        @loader.select_feed(@loader.feed, refresh: true)
      end
      @selector = Gtk::DropDown.new_from_strings(HN::Feed.names)
      @selector.selected = HN::Feed.values.index(initial_feed).not_nil!.to_u32
      @selector.notify_signal["selected"].connect do
        @check_after_load = true
        @loader.select_feed(HN::Feed.values[@selector.selected.to_i])
      end
      @list.row_activated_signal.connect do |row|
        if item = @loader.items[row.index]?
          on_selected.call(item)
        end
      end

      build
      connect_scroll_restoration
      @update_timer = GLib.timeout_seconds(60_u32) do
        @loader.check_for_updates
        true
      end
    end

    def load : Nil
      @loader.select_feed(HN::Feed.values[@selector.selected.to_i])
    end

    def remember_position : Nil
      @scroll_position = @widget.vadjustment.value
    end

    def close : Nil
      @closed = true
      @loader.cancel
      if timer = @update_timer
        GLib::Source.remove(timer)
        @update_timer = nil
      end
    end

    private def build : Nil
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 18)
      Widgets.margins(content)
      content.append(Widgets.label("Hacker News", "title-1"))
      content.append(Widgets.label("Stories and conversations from the community.", "dim-label"))

      @more_button.halign = Gtk::Align::Center
      {@list, @spinner, @status, @more_button}.each { |child| content.append(child) }
      @widget.child = Adw::Clamp.new(maximum_size: 900, child: content)
    end

    private def connect_scroll_restoration : Nil
      @widget.map_signal.connect do
        # Restore after GTK has allocated the mapped page and its adjustment.
        GLib.idle_add do
          @widget.vadjustment.value = @scroll_position unless @closed
          false
        end
      end
    end

    private def update : Nil
      return if @closed

      update_rows
      @spinner.spinning = @loader.loading?
      @spinner.visible = @loader.loading?
      @refresh_button.sensitive = !@loader.loading?
      count = @loader.new_posts_count
      @updates_banner.title = count == 1 ? "1 new post available" : "#{count} new posts available"
      @updates_banner.revealed = count > 0
      @updates_banner.sensitive = !@loader.loading?
      message = status_message
      @status.label = message
      @status.visible = !message.empty?
      @more_button.label = @loader.error ? "Retry" : "Load More"
      @more_button.visible = !@loader.error.nil? || @loader.has_more?
      @more_button.sensitive = !@loader.loading?
      if @check_after_load && !@loader.loading? && @loader.error.nil?
        @check_after_load = false
        @loader.check_for_updates
      end
    end

    private def status_message : String
      if error = @loader.error
        return error
      end
      return "No stories found." if @loader.items.empty? && !@loader.loading?

      ""
    end

    private def update_rows : Nil
      ids = @loader.items.map(&.id)
      return if ids == @rendered_ids

      # Append pages without disturbing scroll position or keyboard focus.
      if ids[0, @rendered_ids.size] != @rendered_ids
        while child = @list.first_child
          @list.remove(child)
        end
        @rendered_ids.clear
      end
      @loader.items.skip(@rendered_ids.size).each { |item| append_story(item) }
      @rendered_ids = ids
    end

    private def append_story(item : HN::Item) : Nil
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 7)
      Widgets.margins(content, 16)
      content.append(Widgets.label(item.title, "heading"))
      if url = item.url
        content.append(Widgets.label(Formatting.domain(url), "caption"))
      end
      content.append(Widgets.label(Formatting.metadata(item), "dim-label"))
      @list.append(Gtk::ListBoxRow.new(child: content))
    end
  end
end
