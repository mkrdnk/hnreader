require "libadwaita"
require "./markup"

module HNReader::UI
  module Widgets
    extend self

    def label(text : String, css : String? = nil) : Gtk::Label
      Gtk::Label.new(
        label: text,
        xalign: 0_f32,
        wrap: true,
        wrap_mode: Pango::WrapMode::WordChar,
        hexpand: true,
      ).tap { |widget| widget.add_css_class(css) if css }
    end

    def button(text : String, &action : -> Nil) : Gtk::Button
      Gtk::Button.new_with_label(text).tap do |widget|
        widget.clicked_signal.connect { action.call }
      end
    end

    def icon_button(icon : String, tooltip : String, &action : -> Nil) : Gtk::Button
      Gtk::Button.new(icon_name: icon, tooltip_text: tooltip).tap do |widget|
        widget.clicked_signal.connect { action.call }
      end
    end

    def save_button(saved : Bool, item_name : String, &toggle : -> Bool) : Gtk::Button
      button = Gtk::Button.new(icon_name: "bookmark-new-symbolic")
      show_saved_state(button, saved, item_name)
      button.clicked_signal.connect do
        show_saved_state(button, toggle.call, item_name)
      end
      button
    end

    def margins(widget : Gtk::Widget, size : Int32 = 18) : Nil
      widget.margin_top = size
      widget.margin_bottom = size
      widget.margin_start = size
      widget.margin_end = size
    end

    def clear(box : Gtk::Box) : Nil
      while child = box.first_child
        box.remove(child)
      end
    end

    def clear(list : Gtk::ListBox) : Nil
      while child = list.first_child
        list.remove(child)
      end
    end

    def rich_text(html : String, &open_link : String -> Nil) : Gtk::Label
      label("").tap do |widget|
        widget.markup = Markup.render(html)
        widget.selectable = true
        widget.activate_link_signal.connect do |url|
          open_link.call(url)
          true
        end
      end
    end

    private def show_saved_state(button : Gtk::Button, saved : Bool, item_name : String) : Nil
      if saved
        button.add_css_class("suggested-action")
        button.tooltip_text = "Remove #{item_name} from saved"
      else
        button.remove_css_class("suggested-action")
        button.tooltip_text = "Save #{item_name}"
      end
    end
  end
end
