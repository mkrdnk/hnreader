require "./theme"
require "../preferences"
require "../hn/client"
require "./widgets"

module HNReader::UI
  class Settings
    getter widget : Adw::Dialog
    @buttons = {} of Theme::Mode => Gtk::ToggleButton
    @updating = false

    def initialize(@theme : Theme, client : HN::Client, preferences : Preferences = Preferences.new)
      @widget = Adw::Dialog.new(title: "Settings", content_width: 380, content_height: 520)
      content = Gtk::Box.new(Gtk::Orientation::Vertical, 0)
      content.append(Adw::HeaderBar.new)
      body = Gtk::Box.new(Gtk::Orientation::Vertical, 16)
      Widgets.margins(body, 24)
      body.append(Widgets.label("Appearance", "title-3"))
      choices = Gtk::Box.new(orientation: Gtk::Orientation::Horizontal, spacing: 14, halign: Gtk::Align::Center)
      error_label = Widgets.label("", "error")
      error_label.visible = false

      Theme::Mode.each do |mode|
        column = Gtk::Box.new(Gtk::Orientation::Vertical, 8)
        button = Gtk::ToggleButton.new(
          tooltip_text: mode.system? ? "Follow system appearance" : "#{mode} theme",
          css_classes: ["theme-swatch", "theme-#{mode.to_s.downcase}"],
          width_request: 56, height_request: 56,
        )
        check = Gtk::Image.new(icon_name: "object-select-symbolic", halign: Gtk::Align::End, valign: Gtk::Align::End,
          css_classes: ["theme-check"])
        button.child = check
        button.active = mode == @theme.mode
        @buttons[mode] = button
        button.toggled_signal.connect do
          unless @updating
            begin
              @theme.select(mode) if button.active?
              error_label.visible = false
            rescue error : File::Error
              error_label.label = "Could not save theme. Check configuration folder permissions."
              error_label.visible = true
            end
            sync_buttons
          end
        end
        column.append(button)
        column.append(Gtk::Label.new(label: mode.to_s, css_classes: ["caption"]))
        choices.append(column)
      end
      body.append(choices)
      body.append(Gtk::Separator.new(orientation: Gtk::Orientation::Horizontal))
      body.append(Widgets.label("Startup", "title-3"))
      startup = Adw::ComboRow.new(
        title: "Default feed",
        subtitle: "Opened when the app starts",
        model: Gtk::StringList.new(HN::Feed.names),
        selected: HN::Feed.values.index(preferences.default_feed).not_nil!.to_u32,
      )
      updating_feed = false
      startup.notify_signal["selected"].connect do
        unless updating_feed
          begin
            preferences.default_feed = HN::Feed.values[startup.selected.to_i]
            error_label.visible = false
          rescue error : File::Error
            error_label.label = "Could not save default feed. Check configuration folder permissions."
            error_label.visible = true
            updating_feed = true
            startup.selected = HN::Feed.values.index(preferences.default_feed).not_nil!.to_u32
            updating_feed = false
          end
        end
      end
      group = Adw::PreferencesGroup.new
      group.add(startup)
      body.append(group)
      body.append(Gtk::Separator.new(orientation: Gtk::Orientation::Horizontal))
      body.append(Widgets.label("Cache", "title-3"))
      body.append(Widgets.label("Remove saved feeds, stories and comments. Your settings are kept.", "dim-label"))
      cache_status = Widgets.label("")
      cache_status.visible = false
      clear_button = Widgets.button("Clear cache") do
        cleared = client.clear_cache
        cache_status.label = cleared ? "Cache cleared." : "Could not remove all cache files. Check cache folder permissions."
        cache_status.visible = true
      end
      clear_button.halign = Gtk::Align::Start
      body.append(clear_button)
      body.append(cache_status)
      body.append(error_label)
      scrolled = Gtk::ScrolledWindow.new(hscrollbar_policy: Gtk::PolicyType::Never, vexpand: true)
      scrolled.child = body
      content.append(scrolled)
      @widget.child = content
    end

    def self.install_styles : Nil
      provider = Gtk::CssProvider.new
      provider.load_from_string(<<-CSS)
        button.theme-swatch {
          border-radius: 999px;
          min-width: 52px;
          min-height: 52px;
          padding: 0;
          border: 2px solid alpha(currentColor, 0.25);
          box-shadow: none;
        }
        button.theme-system { background: linear-gradient(135deg, #ffffff 49.5%, #2c2c2c 50.5%); }
        button.theme-light { background: #ffffff; }
        button.theme-sepia { background: #f1e9dc; }
        button.theme-dark { background: #2c2c2c; }
        button.theme-swatch:checked { border-color: @accent_bg_color; }
        button.theme-swatch:focus-visible { outline: 2px solid @accent_bg_color; outline-offset: 4px; }
        .theme-check { opacity: 0; border-radius: 999px; padding: 2px; background: @accent_bg_color; color: @accent_fg_color; }
        :checked > .theme-check { opacity: 1; }
      CSS
      if display = Gdk::Display.default
        Gtk::StyleContext.add_provider_for_display(display, provider, 600_u32)
      end
    end

    private def sync_buttons : Nil
      @updating = true
      @buttons.each { |mode, button| button.active = mode == @theme.mode }
      @updating = false
    end
  end
end
