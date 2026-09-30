require "libadwaita"

module HNReader::UI
  class Theme
    enum Mode
      System
      Light
      Sepia
      Dark
    end

    getter mode : Mode
    @sepia = Gtk::CssProvider.new

    def initialize(@path : String = File.join(ENV["XDG_CONFIG_HOME"]? || File.join(Path.home.to_s, ".config"), "hnreader", "theme"))
      @mode = read
      @sepia.load_from_string(<<-CSS)
        @define-color window_bg_color #f1e9dc;
        @define-color window_fg_color #433b30;
        @define-color view_bg_color #f7f0e5;
        @define-color view_fg_color #433b30;
        @define-color headerbar_bg_color #e9dfce;
        @define-color headerbar_fg_color #433b30;
        @define-color card_bg_color #faf4ea;
        @define-color card_fg_color #433b30;
        @define-color dialog_bg_color #f1e9dc;
        @define-color dialog_fg_color #433b30;
        @define-color popover_bg_color #f7f0e5;
        @define-color popover_fg_color #433b30;
      CSS
      apply
    end

    def select(mode : Mode) : Nil
      # Persist first so a failed write does not silently lose the preference.
      Dir.mkdir_p(File.dirname(@path))
      File.write("#{@path}.tmp", mode.to_s.downcase)
      File.rename("#{@path}.tmp", @path)
      @mode = mode
      apply
    end

    private def read : Mode
      Mode.parse?(File.read(@path).strip) || Mode::System
    rescue File::Error
      Mode::System
    end

    private def apply : Nil
      manager = Adw::StyleManager.default
      manager.color_scheme = case @mode
                             when .system? then Adw::ColorScheme::Default
                             when .dark?   then Adw::ColorScheme::ForceDark
                             else               Adw::ColorScheme::ForceLight
                             end
      if display = Gdk::Display.default
        Gtk::StyleContext.remove_provider_for_display(display, @sepia)
        if @mode.sepia?
          Gtk::StyleContext.add_provider_for_display(display, @sepia, 600_u32)
        end
      end
    end
  end
end
