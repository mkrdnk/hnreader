require "./article_view"
require "./comments_view"
require "./formatting"
require "../saved_items"
require "./reading_position"

module HNReader::UI
  class StoryView
    getter widget = Gtk::Box.new(Gtk::Orientation::Vertical, 0)

    @pages = Gtk::Stack.new(vexpand: true)
    @article_box = Gtk::Box.new(Gtk::Orientation::Vertical, 0)
    @discussion_box = Gtk::Box.new(Gtk::Orientation::Vertical, 16)
    @save_actions = Gtk::Box.new(Gtk::Orientation::Horizontal, 8)
    @title = Widgets.label("", "title-2")
    @metadata = Widgets.label("", "dim-label")
    @requests = HTTP::RequestGroup.new
    @comments : CommentsView?
    @article : ArticleView?
    @selected : HN::Item?
    @discussion_scroll = Gtk::ScrolledWindow.new(hscrollbar_policy: Gtk::PolicyType::Never)
    @discussion_position : ReadingPosition?
    @reading : ReadingState?

    def initialize(@client : HN::Client, @saved : SavedItems, @preferences : Preferences,
                   @history : ReadingHistory,
                   &@open_external : String -> Nil)
      build
      @pages.notify_signal["visible-child-name"].connect do
        if reading = @reading
          reading.page = @pages.visible_child_name || "discussion"
          load_visible_page
        end
      end
    end

    def show(item : HN::Item) : Nil
      close
      @requests = HTTP::RequestGroup.new
      @selected = item
      reading = @history.story(item.id)
      reading.read = true
      last_page = reading.page
      @article = nil
      Widgets.clear(@article_box)
      Widgets.clear(@discussion_box)
      @title.label = item.title
      @metadata.label = Formatting.metadata(item)
      Widgets.clear(@save_actions)
      @save_actions.append(Widgets.save_button(@saved.saved?(item), "article") { @saved.toggle(item) })
      unread = Widgets.button("Mark as unread") do
        reading.read = false
      end
      unread.clicked_signal.connect do
        unread.label = "Marked as unread"
        unread.sensitive = false
      end
      @save_actions.append(unread)
      build_discussion(item, reading)

      has_article = item.url.try { |url| WebURL.valid?(url) } || false
      @pages.page(@article_box).visible = has_article
      @pages.visible_child_name = has_article && last_page != "discussion" ? "article" : "discussion"
      @reading = reading
      reading.page = @pages.visible_child_name.not_nil!
      load_visible_page
    end

    def close : Nil
      @discussion_position.try(&.close)
      @discussion_position = nil
      @reading = nil
      @requests.cancel
      @article.try(&.stop)
    end

    private def build : Nil
      heading = Gtk::Box.new(Gtk::Orientation::Vertical, 8)
      Widgets.margins(heading)
      @title.selectable = true
      heading.append(@title)
      heading.append(@metadata)
      @save_actions.halign = Gtk::Align::End
      heading.append(@save_actions)
      @widget.append(heading)

      @widget.append(Gtk::StackSwitcher.new(
        stack: @pages,
        halign: Gtk::Align::Center,
        margin_bottom: 12,
      ))
      @pages.add_titled(@article_box, "article", "Article")

      Widgets.margins(@discussion_box)
      @discussion_scroll.child = Adw::Clamp.new(maximum_size: 850, child: @discussion_box)
      @pages.add_titled(@discussion_scroll, "discussion", "Discussion")
      @widget.append(@pages)
    end

    private def build_discussion(item : HN::Item, reading : ReadingState) : Nil
      unless item.text.empty?
        @discussion_box.append(Widgets.rich_text(item.text) { |url| open_link(url) })
      end
      comments = CommentsView.new(@client, item.kids, @requests, 0, @saved, reading, item.id) { |url| open_link(url) }
      @comments = comments
      @discussion_box.append(comments.widget)
      @discussion_position = ReadingPosition.new(@discussion_scroll, reading, "discussion") { comments.restored? }
    end

    private def load_visible_page : Nil
      if @pages.visible_child_name == "discussion"
        @comments.try(&.load)
      elsif item = @selected
        ensure_article(item.url)
      end
    end

    private def ensure_article(url : String?) : Nil
      return if @article || !url

      article = ArticleView.new(@preferences, @reading.not_nil!, &@open_external)
      @article = article
      @article_box.append(article.widget)
      article.load(url)
    end

    private def open_link(url : String) : Nil
      return unless WebURL.valid?(url)

      @pages.page(@article_box).visible = true
      if article = @article
        article.load(url)
      else
        ensure_article(url)
      end
      @pages.visible_child_name = "article"
    end
  end
end
