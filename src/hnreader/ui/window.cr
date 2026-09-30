require "../constants"
require "../saved_items"
require "./feed_view"
require "./saved_view"
require "./story_view"
require "./settings"
require "./icons"

module HNReader::UI
  class Window
    getter widget : Adw::ApplicationWindow

    @navigation = Gtk::Stack.new(
      vexpand: true,
      transition_type: Gtk::StackTransitionType::SlideLeftRight,
    )
    @feed_view : FeedView
    @saved_view : SavedView
    @story_view : StoryView
    @back_button : Gtk::Button
    @saved_button : Gtk::Button
    @theme : Theme
    @preferences = Preferences.new
    @back_destination = "feed"

    def initialize(application : Adw::Application, @client : HN::Client,
                   saved : SavedItems = SavedItems.new)
      Icons.install
      @widget = Adw::ApplicationWindow.new(
        application: application,
        title: APPLICATION_NAME,
        default_width: 960,
        default_height: 760,
      )
      @theme = Theme.new
      Settings.install_styles
      @feed_view = FeedView.new(client, @preferences.default_feed) { |item| show_story(item) }
      @saved_view = SavedView.new(
        client,
        saved,
        ->(item : HN::Item) { show_story(item) },
        ->(url : String) { open_external(url) }
      )
      @story_view = StoryView.new(client, saved) { |url| open_external(url) }
      @back_button = Widgets.icon_button("go-previous-symbolic", "Go back") { go_back }
      @saved_button = Widgets.icon_button("user-bookmarks-symbolic", "Saved items") { show_saved }
      @back_button.visible = false

      build
      @widget.close_request_signal.connect do
        @feed_view.close
        @saved_view.close
        @story_view.close
        false
      end
      @feed_view.load
    end

    def show_story(item : HN::Item) : Nil
      origin = @navigation.visible_child_name
      if origin == "feed"
        @feed_view.remember_position
        @back_destination = "feed"
      elsif origin == "saved"
        @saved_view.close
        @back_destination = "saved"
      end
      @story_view.show(item)
      @navigation.visible_child_name = "story"
      show_feed_controls(false)
    end

    def show_feed : Nil
      @saved_view.close
      @story_view.close
      @navigation.visible_child_name = "feed"
      @back_destination = "feed"
      show_feed_controls(true)
    end

    def show_saved : Nil
      @story_view.close
      @saved_view.show
      @navigation.visible_child_name = "saved"
      @back_destination = "feed"
      show_feed_controls(false)
    end

    private def build : Nil
      header = Adw::HeaderBar.new(
        title_widget: Gtk::Label.new(label: APPLICATION_NAME, css_classes: ["heading"]),
      )
      header.pack_start(@back_button)
      header.pack_start(@feed_view.selector)
      header.pack_end(Widgets.icon_button("help-about-symbolic", "About HN Reader") { show_about })
      header.pack_end(Widgets.icon_button("emblem-system-symbolic", "Settings") do
        Settings.new(@theme, @client, @preferences).widget.present(@widget)
      end)
      header.pack_end(@saved_button)
      header.pack_end(@feed_view.refresh_button)

      @navigation.add_named(@feed_view.widget, "feed")
      @navigation.add_named(@saved_view.widget, "saved")
      @navigation.add_named(@story_view.widget, "story")
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 0)
      content.append(header)
      content.append(@feed_view.updates_banner)
      content.append(@navigation)
      @widget.content = content
    end

    private def go_back : Nil
      if @back_destination == "saved"
        show_saved
      else
        show_feed
      end
    end

    private def show_about : Nil
      dialog = Adw::AboutDialog.new(
        application_name: APPLICATION_NAME,
        application_icon: APPLICATION_ID,
        version: VERSION,
        comments: "A native GNOME reader for Hacker News. Browse feeds, read discussions, and view articles in an embedded browser.",
        license_type: Gtk::License::Gpl30Only,
      )
      dialog.add_link("GitHub", GITHUB_URL)
      dialog.add_link("Hacker News", HN_URL)
      dialog.add_link("Author", AUTHOR_URL)
      dialog.activate_link_signal.connect do |url|
        open_external(url)
        true
      end
      dialog.present(@widget)
    end

    private def show_feed_controls(visible : Bool) : Nil
      @back_button.visible = !visible
      @feed_view.selector.visible = visible
      @feed_view.refresh_button.visible = visible
      @feed_view.updates_banner.visible = visible
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
