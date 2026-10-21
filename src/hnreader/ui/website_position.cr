require "../reading_history"

module HNReader::UI
  # An isolated script world keeps article scripts away from the history bridge.
  # Only the top frame reports scroll offsets, scoped to the current document.
  class WebsitePosition
    WORLD = "hnreader-reading"

    @generation = 0
    @closed = false

    def initialize(@web : WebKit::WebView, @state : ReadingState)
      manager = @web.user_content_manager
      manager.register_script_message_handler("readingPosition", WORLD)
      manager.script_message_received_signal["readingPosition"].connect do |value|
        receive(value.to_string)
      end
      @web.map_signal.connect { restore }
    end

    def prepare : Nil
      @generation += 1
      source = <<-JS
        (() => {
          const positions = #{@state.website_positions.to_json};
          const generation = #{@generation};
          let ready = false;
          globalThis.restoreReadingPosition = (y) => {
            ready = false;
            requestAnimationFrame(() => requestAnimationFrame(() => {
              window.scrollTo(0, y);
              requestAnimationFrame(() => { ready = true; });
            }));
          };
          window.addEventListener('load', () => {
            restoreReadingPosition(positions['website:' + location.href] || 0);
          }, {once: true});
          window.addEventListener('scroll', () => {
            if (ready) {
              window.webkit.messageHandlers.readingPosition.postMessage(
                JSON.stringify({generation, url: location.href, y: window.scrollY}));
            }
          }, {passive: true});
        })();
        JS
      manager = @web.user_content_manager
      manager.remove_all_scripts
      manager.add_script(WebKit::UserScript.new_for_world(
        source, WebKit::UserContentInjectedFrames::TopFrame,
        WebKit::UserScriptInjectionTime::Start, WORLD, nil, nil
      ))
    end

    def close : Nil
      @closed = true
      @web.user_content_manager.unregister_script_message_handler("readingPosition", WORLD)
    end

    private def restore : Nil
      return if @closed
      return unless url = @web.uri?

      script = "globalThis.restoreReadingPosition?.(#{@state.position("website:#{url}")})"
      @web.evaluate_javascript(script, -1_i64, WORLD, nil, nil) do |source, result|
        begin
          WebKit::WebView.cast(source).evaluate_javascript_finish(result)
        rescue GLib::Error
          # Navigation can replace the document before this callback completes.
        end
      end
    end

    private def receive(message : String) : Nil
      return if @closed || !@web.mapped

      data = JSON.parse(message)
      return unless data["generation"].as_i == @generation
      return unless data["url"].as_s == @web.uri?

      offset = data["y"].as_f? || data["y"].as_i64.to_f64
      @state.remember_position("website:#{data["url"].as_s}", offset)
    rescue JSON::ParseException | TypeCastError | KeyError
      # Ignore malformed messages; they must not affect navigation.
    end
  end
end
