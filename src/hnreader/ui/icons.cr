require "libadwaita"
require "../constants"

module HNReader::UI
  module Icons
    # Embed in every build, including debug builds and release archives.
    DATA = {{ read_file("#{__DIR__}/../../../.build/hnreader.gresource") }}
    @@resource : Gio::Resource?

    def self.install : Nil
      unless @@resource
        resource = Gio::Resource.new_from_data(GLib::Bytes.new(DATA.to_unsafe, DATA.bytesize))
        resource._register
        @@resource = resource
      end
      if display = Gdk::Display.default
        Gtk::IconTheme.for_display(display).add_resource_path("/com/makridenko/hnreader/icons")
      end
      Gtk::Window.default_icon_name = APPLICATION_ID
    end
  end
end
