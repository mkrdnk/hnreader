require "libadwaita"
require "./constants"
require "./http/soup_transport"
require "./saved_items"
require "./ui/window"

module HNReader
  class Application
    @application : Adw::Application
    @window : UI::Window?

    def initialize
      @application = Adw::Application.new(APPLICATION_ID, Gio::ApplicationFlags::None)
      @application.activate_signal.connect { activate }
    end

    def run : Int32
      Application.run_main_loop(@application)
    end

    def self.run_main_loop(application : Gio::Application) : Int32
      # gi-crystal's run wrapper moves the loop onto an isolated fiber stack.
      # JavaScriptCore's UI-process VM scans/sanitizes the native thread stack;
      # invoking it from that fiber can corrupt memory. Keep GTK/WebKit callbacks
      # on the original main-thread stack. Networking uses async Soup, not fibers.
      LibGio.g_application_run(application, ARGC_UNSAFE, ARGV_UNSAFE)
    end

    private def activate : Nil
      window = @window ||= UI::Window.new(
        @application,
        HN::Client.new(HTTP::SoupTransport.new, cache: HN::Cache.new(HN::Cache.default_directory)),
        SavedItems.new
      )
      window.widget.present
    end
  end
end
