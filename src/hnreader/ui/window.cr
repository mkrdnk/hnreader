require "../constants"
require "./feed_view"
require "./story_view"
require "./settings"

module HNReader::UI
  class Window
    getter widget : Adw::ApplicationWindow

    @navigation = Gtk::Stack.new(
      vexpand: true,
      transition_type: Gtk::StackTransitionType::SlideLeftRight,
    )
    @feed_view : FeedView
    @story_view : StoryView
    @back_button : Gtk::Button
    @theme : Theme

    def initialize(application : Adw::Application, client : HN::Client)
      @widget = Adw::ApplicationWindow.new(
        application: application,
        title: APPLICATION_NAME,
        default_width: 960,
        default_height: 760,
      )
      @theme = Theme.new
      Settings.install_styles
      @feed_view = FeedView.new(client) { |item| show_story(item) }
      @story_view = StoryView.new(client) { |url| open_external(url) }
      @back_button = Widgets.icon_button("go-previous-symbolic", "Back to feed") { show_feed }
      @back_button.visible = false

      build
      @widget.close_request_signal.connect do
        @feed_view.close
        @story_view.close
        false
      end
      @feed_view.load
    end

    def show_story(item : HN::Item) : Nil
      @feed_view.remember_position
      @story_view.show(item)
      @navigation.visible_child_name = "story"
      show_feed_controls(false)
    end

    def show_feed : Nil
      @story_view.close
      @navigation.visible_child_name = "feed"
      show_feed_controls(true)
    end

    private def build : Nil
      header = Adw::HeaderBar.new(
        title_widget: Gtk::Label.new(label: APPLICATION_NAME, css_classes: ["heading"]),
      )
      header.pack_start(@back_button)
      header.pack_start(@feed_view.selector)
      header.pack_end(Widgets.icon_button("emblem-system-symbolic", "Settings") do
        Settings.new(@theme).widget.present(@widget)
      end)
      header.pack_end(@feed_view.refresh_button)

      @navigation.add_named(@feed_view.widget, "feed")
      @navigation.add_named(@story_view.widget, "story")
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 0)
      content.append(header)
      content.append(@navigation)
      @widget.content = content
    end

    private def show_feed_controls(visible : Bool) : Nil
      @back_button.visible = !visible
      @feed_view.selector.visible = visible
      @feed_view.refresh_button.visible = visible
    end

    private def open_external(url : String) : Nil
      return unless WebURL.valid?(url)

      Gtk::UriLauncher.new(url).launch(@widget, nil) do |launcher, result|
        begin
          Gtk::UriLauncher.cast(launcher).launch_finish(result)
        rescue error : GLib::Error
          dialog = Adw::AlertDialog.new("Could not open browser", error.message)
          dialog.add_response("ok", "OK")
          dialog.present(@widget)
        end
      end
    end
  end
end
