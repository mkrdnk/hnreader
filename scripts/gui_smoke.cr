# Opt-in integration test. Run via scripts/gui-smoke.sh in a desktop session.
require "../src/hnreader/application"
require "../spec/support/gui_access"

module HNReader::Testing
  class GuiSmoke
    INTERVAL_MS = 150_u32
    MAX_TICKS   =     700

    enum Step
      InitialFeed
      FailedPage
      RetriedPage
      Feeds
      Article
      NextPage
      PreviousPage
      Discussion
      Replies
      BackToFeed
      ReadingMore
      ReadingDeep
      ReadingArticle
      ReadingRestart
      ReadingRestoredArticle
      ReadingRestoredDiscussion
      ReadingWebsite
      ReadingWebsiteScroll
      ReadingRestoredWebsite
      NarrowLayout
      Settings
      About
      ServerStats
    end

    @application : Adw::Application
    @window : UI::Window?
    @base_url : String
    @output_directory : String
    @step = Step::InitialFeed
    @ticks = 0
    @feeds = HN::Feed.values.dup
    @scroll_position = 0.0
    @failed = false
    @completed = false
    @settings : UI::Settings?
    @discussion_offset = 0.0
    @article_offset = 0.0
    @website_offset = 0.0
    @history_path = File.join(ENV["XDG_CONFIG_HOME"], "reading-history.json")

    def initialize
      @application = Adw::Application.new("#{APPLICATION_ID}.Smoke", Gio::ApplicationFlags::NonUnique)
      @base_url = ENV["HN_SMOKE_URL"]
      @output_directory = ENV["HN_SMOKE_OUTPUT"]
      @application.activate_signal.connect { start }
    end

    def run : Int32
      Application.run_main_loop(@application)
      STDERR.puts "GUI smoke exited before completion at #{@step}" unless @completed || @failed
      @completed && !@failed ? 0 : 1
    end

    private def start : Nil
      Adw::StyleManager.default.color_scheme = Adw::ColorScheme::ForceLight
      client = HN::Client.new(HTTP::SoupTransport.new, "#{@base_url}/v0")
      preferences = Preferences.new(
        File.join(@output_directory, "default-feed"),
        File.join(@output_directory, "reader-mode"),
      )
      preferences.default_feed = HN::Feed::New
      saved = SavedItems.new(File.join(@output_directory, "saved-items.json"))
      @window = UI::Window.new(@application, client, saved, preferences, ReadingHistory.new(@history_path))
      window.widget.present
      GLib.timeout_milliseconds(INTERVAL_MS) { tick }
    rescue error
      fail_test(error)
    end

    private def window : UI::Window
      @window.not_nil!
    end

    private def tick : Bool
      @ticks += 1
      raise "GUI smoke timed out at #{@step}" if @ticks > MAX_TICKS

      case @step
      in .initial_feed?                then check_initial_feed
      in .failed_page?                 then check_failed_page
      in .retried_page?                then check_retried_page
      in .feeds?                       then check_feeds
      in .article?                     then check_article
      in .next_page?                   then check_next_page
      in .previous_page?               then check_previous_page
      in .discussion?                  then expand_replies
      in .replies?                     then check_replies
      in .back_to_feed?                then check_back_to_feed
      in .reading_more?                then check_reading_more
      in .reading_deep?                then check_reading_deep
      in .reading_article?             then check_reading_article
      in .reading_restart?             then restart_reading
      in .reading_restored_article?    then check_restored_article
      in .reading_restored_discussion? then check_restored_discussion
      in .reading_website?             then check_reading_website
      in .reading_website_scroll?      then check_website_scroll
      in .reading_restored_website?    then check_restored_website
      in .narrow_layout?               then check_narrow_layout
      in .settings?                    then check_settings
      in .about?                       then check_about
      in .server_stats?
        # The async stats request completes the test.
      end
      true
    rescue error
      fail_test(error)
      false
    end

    private def check_initial_feed : Nil
      loader = window.feed_view.loader
      return if loader.loading?

      check(loader.error.nil?, "Initial feed failed")
      check(loader.feed == HN::Feed::New, "Saved startup feed was not loaded")
      check(window.feed_view.selector.selected == HN::Feed.values.index(HN::Feed::New), "Feed selector does not match startup feed")
      check(loader.items.map(&.id) == (1_i64..30_i64).to_a, "Feed order/count incorrect")
      return unless capture("01-feed-light")
      loader.load_more
      @step = Step::FailedPage
    end

    private def check_failed_page : Nil
      loader = window.feed_view.loader
      return if loader.loading?

      check(!loader.error.nil?, "Expected recoverable HTTP 503")
      loader.load_more
      @step = Step::RetriedPage
    end

    private def check_retried_page : Nil
      loader = window.feed_view.loader
      return if loader.loading?

      check(loader.items.size == 31, "Retry lost or duplicated items")
      @step = Step::Feeds
    end

    private def check_feeds : Nil
      loader = window.feed_view.loader
      return if loader.loading?

      check(loader.error.nil?, "Feed request failed")
      if feed = @feeds.shift?
        loader.select_feed(feed)
      else
        adjustment = window.feed_view.widget.vadjustment
        adjustment.value = 350.0
        @scroll_position = adjustment.value
        window.show_story(loader.items.first)
        @step = Step::Article
      end
    end

    private def check_article : Nil
      article = window.story_view.article.not_nil!
      web = article.web
      return unless web.title? == "Smoke article"
      return unless article.pages.visible_child_name == "reader"

      check(web.is_loading?, "Reader mode waited for non-document resources")
      reader_labels = widgets(article.reader_content).compact_map(&.as?(Gtk::Label))
      check(reader_labels.size >= 5, "Reader content was not split into native blocks")
      reader_text = reader_labels.map(&.label).join(" ")
      check(reader_text.includes?("native reader extracts the main article"), "Native reader content missing")
      check(article.reader_button.active?, "Reader mode was not enabled by default")
      return unless capture("02-article")
      web.load_uri("#{@base_url}/second")
      @step = Step::NextPage
    end

    private def check_next_page : Nil
      web = window.story_view.article.not_nil!.web
      return unless web.title? == "Second page" && !web.is_loading?

      check(web.can_go_back, "No website history")
      web.go_back
      @step = Step::PreviousPage
    end

    private def check_previous_page : Nil
      return unless window.story_view.article.not_nil!.web.title? == "Smoke article"

      window.story_view.pages.visible_child_name = "discussion"
      @step = Step::Discussion
    end

    private def expand_replies : Nil
      expanders = widgets(window.story_view.discussion_box).compact_map(&.as?(Gtk::Expander))
      return if expanders.empty?

      expanders.each { |expander| expander.expanded = true }
      @step = Step::Replies
    end

    private def check_replies : Nil
      texts = discussion_texts
      return unless texts.count { |text| text.includes?("A native comment") } >= 2

      check(texts.includes?("[deleted]"), "Deleted comment placeholder missing")
      return unless capture("03-discussion")
      window.show_feed
      @step = Step::BackToFeed
    end

    private def check_back_to_feed : Nil
      return if window.navigation.transition_running?

      adjustment = window.feed_view.widget.vadjustment
      check((adjustment.value - @scroll_position).abs < 1.0, "Feed scroll was lost")
      check(window.history.read?(1_i64), "Opened story was not marked read")
      title = widgets(window.feed_view.list.row_at_index(0).not_nil!).compact_map(&.as?(Gtk::Label)).first
      check(title.has_css_class("dim-label"), "Read title was not dimmed")
      window.feed_view.unread_only.active = true
      check(!window.feed_view.rendered_ids.includes?(1_i64), "Read story remains in unread filter")
      # Activation must use the filtered row IDs, not the unfiltered loader index.
      window.feed_view.list.row_activated_signal.emit(window.feed_view.list.row_at_index(0).not_nil!)
      check(window.story_view.pages.visible_child_name == "discussion", "Filtered row opened the wrong story")
      window.show_feed
      window.feed_view.unread_only.active = false
      window.show_story(window.feed_view.loader.items.first)
      check(window.story_view.pages.visible_child_name == "discussion", "Last reading tab was not restored")
      @step = Step::ReadingMore
    end

    private def check_reading_more : Nil
      comments = window.story_view.comments.not_nil!
      return unless comments.restored?

      comments.more.clicked_signal.emit
      @step = Step::ReadingDeep
    end

    private def check_reading_deep : Nil
      comments = window.story_view.comments.not_nil!
      return unless comments.restored?
      return unless window.history.story(1_i64).loaded_count(1_i64) == 32

      # Expand the page-two branch, then its child as it arrives.
      expanders = widgets(window.story_view.discussion_box).compact_map(&.as?(Gtk::Expander))
      expanders.each { |expander| expander.expanded = true }
      return unless window.history.story(1_i64).expanded?(201_i64)
      return unless comments.restored?
      return unless window.story_view.discussion_position.not_nil!.restored?

      adjustment = window.story_view.discussion_scroll.vadjustment
      adjustment.value = 2100.0
      @discussion_offset = adjustment.value
      check(@discussion_offset > 0, "Discussion fixture is not scrollable")
      window.story_view.pages.visible_child_name = "article"
      @step = Step::ReadingArticle
    end

    private def check_reading_article : Nil
      article = window.story_view.article.not_nil!
      check(article.reader_button.active?, "Reader mode was changed without a user choice")
      return unless article.reader_position.try(&.restored?)

      article.reader_scroll.vadjustment.value = 600.0
      @article_offset = article.reader_scroll.vadjustment.value
      check(@article_offset > 0, "Article fixture is not scrollable")
      @step = Step::ReadingRestart
    end

    private def recreate_window : Nil
      old = window
      # Keep an application window alive while closing the old one, then reload
      # from disk rather than sharing the old ReadingHistory object.
      placeholder = Adw::ApplicationWindow.new(application: @application)
      placeholder.present
      old.widget.close
      @window = UI::Window.new(
        @application,
        HN::Client.new(HTTP::SoupTransport.new, "#{@base_url}/v0"),
        SavedItems.new(File.join(@output_directory, "saved-items.json")),
        old.preferences,
        ReadingHistory.new(@history_path)
      )
      window.widget.present
      placeholder.close
    end

    private def restart_reading : Nil
      recreate_window
      @step = Step::ReadingRestoredArticle
    end

    private def check_restored_article : Nil
      return if window.feed_view.loader.loading?
      if window.navigation.visible_child_name != "story"
        check(window.history.read?(1_i64), "Read mark did not survive restart")
        window.show_story(window.feed_view.loader.items.first)
      end
      article = window.story_view.article.not_nil!
      return unless article.reader_position.try(&.restored?)

      check((article.reader_scroll.vadjustment.value - @article_offset).abs < 1, "Article position did not survive restart")
      window.story_view.pages.visible_child_name = "discussion"
      @step = Step::ReadingRestoredDiscussion
    end

    private def check_restored_discussion : Nil
      return unless window.story_view.discussion_position.not_nil!.restored?
      check((window.story_view.discussion_scroll.vadjustment.value - @discussion_offset).abs < 1, "Discussion position did not survive restart")
      expanders = widgets(window.story_view.discussion_box).compact_map(&.as?(Gtk::Expander))
      check(expanders.size == 4 && expanders.all?(&.expanded), "Deep/page-two expansions were not restored")
      # Collapsing one branch must persist too.
      expanders.first.expanded = false
      unread = widgets(window.story_view.widget).compact_map(&.as?(Gtk::Button)).find { |button| button.label == "Mark as unread" }.not_nil!
      unread.clicked_signal.emit
      window.show_feed
      check(!ReadingHistory.new(@history_path).read?(1_i64), "Mark unread was not persisted")
      check(window.history.story(1_i64).position("discussion") == @discussion_offset, "Mark unread erased progress")
      title = widgets(window.feed_view.list.row_at_index(0).not_nil!).compact_map(&.as?(Gtk::Label)).first
      check(!title.has_css_class("dim-label"), "Unread title is still dimmed")
      window.feed_view.unread_only.active = true
      check(window.feed_view.rendered_ids.includes?(1_i64), "Marked unread story did not return to the filter")
      window.feed_view.unread_only.active = false
      window.show_story(window.feed_view.loader.items.first)
      window.story_view.pages.visible_child_name = "article"
      window.story_view.article.not_nil!.reader_button.active = false
      @step = Step::ReadingWebsite
    end

    private def check_reading_website : Nil
      web = window.story_view.article.not_nil!.web
      return if web.is_loading?

      web.evaluate_javascript("window.scrollTo(0, 850)", -1_i64, nil, nil, nil) do |source, result|
        WebKit::WebView.cast(source).evaluate_javascript_finish(result)
      end
      @step = Step::ReadingWebsiteScroll
    end

    private def check_website_scroll : Nil
      @website_offset = window.history.story(1_i64).position("website:#{@base_url}/article")
      return if @website_offset <= 0

      recreate_window
      @step = Step::ReadingRestoredWebsite
    end

    private def check_restored_website : Nil
      return if window.feed_view.loader.loading?
      if window.navigation.visible_child_name != "story"
        window.show_story(window.feed_view.loader.items.first)
      end
      article = window.story_view.article.not_nil!
      check(!article.reader_button.active?, "Original website mode was not restored")
      return if article.web.is_loading?

      article.web.evaluate_javascript("window.scrollY", -1_i64, nil, nil, nil) do |source, result|
        offset = WebKit::WebView.cast(source).evaluate_javascript_finish(result).to_double
        next if offset == 0
        begin
          check((offset - @website_offset).abs < 1, "Website position did not survive restart")
          check(!window.history.story(1_i64).expanded?(101_i64), "Collapsed branch did not survive restart")
          start_narrow_layout
        rescue error
          fail_test(error)
        end
      end
    end

    private def start_narrow_layout : Nil
      window.show_story(window.feed_view.loader.items[1])
      check(window.story_view.pages.visible_child_name == "discussion", "Text post opened Article")
      check(window.story_view.article.nil?, "Text post created WebKit unnecessarily")
      window.widget.set_default_size(420, 720)
      Adw::StyleManager.default.color_scheme = Adw::ColorScheme::ForceDark
      @step = Step::NarrowLayout
    end

    private def check_narrow_layout : Nil
      return if window.navigation.transition_running? || window.widget.width > 440
      return unless discussion_texts.any?(&.includes?("A native comment"))

      return unless capture("04-narrow-dark")
      window.theme.select(UI::Theme::Mode::Sepia)
      @settings = UI::Settings.new(window.theme, window.client, window.preferences)
      @settings.not_nil!.widget.present(window.widget)
      @ticks = 0
      @step = Step::Settings
    end

    private def check_settings : Nil
      return if @ticks < 5
      return unless capture("05-settings-sepia")
      buttons = widgets(@settings.not_nil!.widget).compact_map(&.as?(Gtk::ToggleButton))
      check(buttons.size == 4, "Expected four theme choices")
      UI::Theme::Mode.values.each_with_index do |mode, index|
        buttons[index].active = true
        check(window.theme.mode == mode, "Theme selection failed")
        check(buttons.count(&.active?) == 1, "Theme selection must be exclusive")
        check(UI::Theme.new.mode == mode, "Theme preference was not persisted")
        scheme = Adw::StyleManager.default.color_scheme
        expected = case mode
                   when .system? then Adw::ColorScheme::Default
                   when .dark?   then Adw::ColorScheme::ForceDark
                   else               Adw::ColorScheme::ForceLight
                   end
        check(scheme == expected, "Incorrect color scheme")
      end
      startup = widgets(@settings.not_nil!.widget).compact_map(&.as?(Adw::ComboRow)).first
      check(startup.selected == HN::Feed.values.index(HN::Feed::New), "Settings did not restore startup feed")
      current_feed = window.feed_view.loader.feed
      startup.selected = HN::Feed.values.index(HN::Feed::Best).not_nil!.to_u32
      check(window.preferences.default_feed == HN::Feed::Best, "Startup feed selection was not saved")
      check(window.feed_view.loader.feed == current_feed, "Startup setting changed the current feed")
      reader_mode = widgets(@settings.not_nil!.widget).compact_map(&.as?(Adw::SwitchRow)).first
      check(reader_mode.active?, "Reader mode setting did not restore its default")
      reader_mode.active = false
      check(!window.preferences.reader_mode?, "Reader mode setting was not applied")
      reader_mode.active = true
      clear_cache = widgets(@settings.not_nil!.widget).compact_map(&.as?(Gtk::Button)).find { |button| button.label == "Clear cache" }.not_nil!
      clear_cache.clicked_signal.emit
      check(widgets(@settings.not_nil!.widget).compact_map(&.as?(Gtk::Label)).any? { |label| label.label == "Cache cleared." && label.visible? }, "Cache clear confirmation missing")
      @settings.not_nil!.widget.close
      about_button = widgets(window.widget).compact_map(&.as?(Gtk::Button)).find do |button|
        button.tooltip_text == "About HN Reader"
      end.not_nil!
      about_button.clicked_signal.emit
      @ticks = 0
      @step = Step::About
    end

    private def check_about : Nil
      return if @ticks < 5
      dialog = window.widget.visible_dialog.as(Adw::AboutDialog)
      check(dialog.application_icon == APPLICATION_ID, "About dialog has the wrong icon")
      # Ignore installed icon directories to verify the embedded fallback independently.
      theme = Gtk::IconTheme.new(display: Gdk::Display.default, theme_name: "hicolor")
      theme.search_path = [ENV["XDG_CONFIG_HOME"]]
      theme.add_resource_path("/com/makridenko/HNReader/icons")
      check(theme.has_icon(APPLICATION_ID), "Embedded application icon is missing")
      icon = theme.lookup_icon(APPLICATION_ID, nil, 128, 1, Gtk::TextDirection::Ltr, Gtk::IconLookupFlags::None)
      check(icon.file.not_nil!.uri.starts_with?("resource:///"), "Application icon was not embedded")
      return unless capture("06-about-icon")
      @step = Step::ServerStats
      HTTP::SoupTransport.new.get("#{@base_url}/stats") do |response|
        begin
          case response
          in Failure then raise response.message
          in String  then peak = JSON.parse(response)["peak"].as_i
          end
          check(peak <= HTTP::SoupTransport::MAX_ACTIVE, "Exceeded HTTP concurrency limit: #{peak}")
          puts "GUI smoke passed: feeds, pagination/retry, unread filter, read marks, native/website/discussion positions across recreated windows, deep comment restoration, WebKit history, text posts, dark/narrow layout; peak HTTP concurrency #{peak}."
          @completed = true
          @application.quit
        rescue exception
          fail_test(exception)
        end
      end
    end

    private def discussion_texts : Array(String)
      widgets(window.story_view.discussion_box).compact_map(&.as?(Gtk::Label)).map(&.text)
    end

    private def widgets(root : Gtk::Widget) : Array(Gtk::Widget)
      result = [root] of Gtk::Widget
      child = root.first_child
      while child
        result.concat(widgets(child))
        child = child.next_sibling
      end
      result
    end

    private def capture(name : String) : Bool
      widget = window.widget
      snapshot = Gtk::Snapshot.new
      Gtk::WidgetPaintable.new(widget).snapshot(snapshot, widget.width.to_f64, widget.height.to_f64)
      node = snapshot.to_node
      renderer = widget.renderer
      return false unless node && renderer

      texture = renderer.render_texture(node, nil)
      check(texture.save_to_png(File.join(@output_directory, "#{name}.png")), "Could not save #{name}")
      true
    end

    private def check(condition : Bool, message : String) : Nil
      raise message unless condition
    end

    private def fail_test(error : Exception) : Nil
      STDERR.puts "GUI smoke failed at #{@step}: #{error.message}\n#{error.backtrace.join('\n')}"
      @failed = true
      @application.quit
    end
  end
end

exit(HNReader::Testing::GuiSmoke.new.run)
