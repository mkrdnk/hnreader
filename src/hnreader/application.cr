require "libadwaita"
require "./constants"
require "./http/soup_transport"
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
      @application.run
    end

    private def activate : Nil
      window = @window ||= UI::Window.new(@application, HN::Client.new(HTTP::SoupTransport.new))
      window.widget.present
    end
  end
end
