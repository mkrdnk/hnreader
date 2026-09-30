require "./article_view"
require "./comments_view"
require "./formatting"
require "../saved_items"

module HNReader::UI
  class StoryView
    getter widget = Gtk::Box.new(Gtk::Orientation::Vertical, 0)

    @pages = Gtk::Stack.new(vexpand: true)
    @article_box = Gtk::Box.new(Gtk::Orientation::Vertical, 0)
    @discussion_box = Gtk::Box.new(Gtk::Orientation::Vertical, 16)
    @save_actions = Gtk::Box.new(Gtk::Orientation::Horizontal, 0)
    @title = Widgets.label("", "title-2")
    @metadata = Widgets.label("", "dim-label")
    @requests = HTTP::RequestGroup.new
    @comments : CommentsView?
    @article : ArticleView?
    @selected : HN::Item?

    def initialize(@client : HN::Client, @saved : SavedItems, @preferences : Preferences,
                   &@open_external : String -> Nil)
      build
      @pages.notify_signal["visible-child-name"].connect { load_visible_page }
    end

    def show(item : HN::Item) : Nil
      close
      @requests = HTTP::RequestGroup.new
      @selected = item
      @article = nil
      Widgets.clear(@article_box)
      Widgets.clear(@discussion_box)
      @title.label = item.title
      @metadata.label = Formatting.metadata(item)
      Widgets.clear(@save_actions)
      @save_actions.append(Widgets.save_button(@saved.saved?(item), "article") { @saved.toggle(item) })
      build_discussion(item)

      has_article = item.url.try { |url| WebURL.valid?(url) } || false
      @pages.page(@article_box).visible = has_article
      @pages.visible_child_name = has_article ? "article" : "discussion"
      load_visible_page
    end

    def close : Nil
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
      scroll = Gtk::ScrolledWindow.new(
        hscrollbar_policy: Gtk::PolicyType::Never,
        child: Adw::Clamp.new(maximum_size: 850, child: @discussion_box),
      )
      @pages.add_titled(scroll, "discussion", "Discussion")
      @widget.append(@pages)
    end

    private def build_discussion(item : HN::Item) : Nil
      unless item.text.empty?
        @discussion_box.append(Widgets.rich_text(item.text) { |url| open_link(url) })
      end
      comments = CommentsView.new(@client, item.kids, @requests, 0, @saved) { |url| open_link(url) }
      @comments = comments
      @discussion_box.append(comments.widget)
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

      article = ArticleView.new(@preferences, &@open_external)
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
