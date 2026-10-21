require "../reading_history"
require "./widgets"

module HNReader::UI
  # Wait for both asynchronous content and GTK allocation before restoring.
  # Hidden/loading pages must never overwrite saved progress with a zero offset.
  class ReadingPosition
    @timer : UInt32?
    @connection : GObject::SignalConnection?
    @closed = false
    @restored = false
    @last_upper = -1.0
    @stable = 0

    def initialize(@scroll : Gtk::ScrolledWindow, @state : ReadingState, @key : String,
                   &@ready : -> Bool)
      @connection = @scroll.vadjustment.value_changed_signal.connect { remember unless @closed }
      @timer = GLib.timeout_milliseconds(100_u32) do
        tick
        @timer = nil if @restored
        !@restored
      end
    end

    def close : Nil
      return if @closed

      remember
      @closed = true
      @connection.try(&.disconnect)
      @connection = nil
      if timer = @timer
        GLib::Source.remove(timer)
        @timer = nil
      end
    end

    private def remember : Nil
      if @restored && @scroll.mapped && @ready.call
        @state.remember_position(@key, @scroll.vadjustment.value)
      end
    end

    private def tick : Nil
      return unless @scroll.mapped && @ready.call

      adjustment = @scroll.vadjustment
      return if adjustment.page_size <= 0

      @stable = adjustment.upper == @last_upper ? @stable + 1 : 0
      @last_upper = adjustment.upper
      return if @stable < 2

      adjustment.value = @state.position(@key).clamp(0.0, Math.max(0.0, adjustment.upper - adjustment.page_size))
      @restored = true
    end
  end
end
