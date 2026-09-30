# Opt-in integration test. Run via scripts/gui-smoke.sh in a desktop session.
require "../src/hnreader/application"
require "../spec/support/gui_access"

module HNReader::Testing
  class GuiSmoke
    INTERVAL_MS = 150_u32
    MAX_TICKS   =     300

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
      NarrowLayout
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

    def initialize
      @application = Adw::Application.new("#{APPLICATION_ID}.Smoke", Gio::ApplicationFlags::NonUnique)
      @base_url = ENV["HN_SMOKE_URL"]
      @output_directory = ENV["HN_SMOKE_OUTPUT"]
      @application.activate_signal.connect { start }
    end

    def run : Int32
      @application.run
      @failed ? 1 : 0
    end

    private def start : Nil
      Adw::StyleManager.default.color_scheme = Adw::ColorScheme::ForceLight
      client = HN::Client.new(HTTP::SoupTransport.new, "#{@base_url}/v0")
      @window = UI::Window.new(@application, client)
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
      in .initial_feed?  then check_initial_feed
      in .failed_page?   then check_failed_page
      in .retried_page?  then check_retried_page
      in .feeds?         then check_feeds
      in .article?       then check_article
      in .next_page?     then check_next_page
      in .previous_page? then check_previous_page
      in .discussion?    then expand_replies
      in .replies?       then check_replies
      in .back_to_feed?  then check_back_to_feed
      in .narrow_layout? then check_narrow_layout
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
      check(loader.items.map(&.id) == (1_i64..30_i64).to_a, "Feed order/count incorrect")
      capture("01-feed-light")
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
      web = window.story_view.article.not_nil!.web
      return unless web.title? == "Smoke article" && !web.is_loading?

      capture("02-article")
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
      capture("03-discussion")
      window.show_feed
      @step = Step::BackToFeed
    end

    private def check_back_to_feed : Nil
      return if window.navigation.transition_running?

      adjustment = window.feed_view.widget.vadjustment
      check((adjustment.value - @scroll_position).abs < 1.0, "Feed scroll was lost")
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

      capture("04-narrow-dark")
      @step = Step::ServerStats
      HTTP::SoupTransport.new.get("#{@base_url}/stats") do |response|
        begin
          case response
          in Failure then raise response.message
          in String  then peak = JSON.parse(response)["peak"].as_i
          end
          check(peak <= HTTP::SoupTransport::MAX_ACTIVE, "Exceeded HTTP concurrency limit: #{peak}")
          puts "GUI smoke passed: feeds, pagination/retry, WebKit history, comments, text posts, scroll, dark/narrow layout; peak HTTP concurrency #{peak}."
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

    private def capture(name : String) : Nil
      widget = window.widget
      snapshot = Gtk::Snapshot.new
      Gtk::WidgetPaintable.new(widget).snapshot(snapshot, widget.width.to_f64, widget.height.to_f64)
      texture = widget.renderer.not_nil!.render_texture(snapshot.to_node.not_nil!, nil)
      check(texture.save_to_png(File.join(@output_directory, "#{name}.png")), "Could not save #{name}")
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
