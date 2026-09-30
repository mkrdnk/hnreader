require "./widgets"

GICrystal.require("WebKit", "6.0")

module HNReader::UI
  class ArticleView
    getter widget = Gtk::Box.new(Gtk::Orientation::Vertical, 0)

    @web : WebKit::WebView
    @progress = Gtk::ProgressBar.new
    @status = Gtk::Label.new(wrap: true, css_classes: ["error"], visible: false)
    @location = Gtk::Label.new(
      hexpand: true,
      ellipsize: Pango::EllipsizeMode::Middle,
      selectable: true,
      css_classes: ["caption"],
    )
    @back_button : Gtk::Button
    @forward_button : Gtk::Button
    @url = ""

    def initialize(&@open_external : String -> Nil)
      # Keep website state in memory, without creating a browser profile.
      session = WebKit::NetworkSession.new_ephemeral
      @web = WebKit::WebView.new(network_session: session, hexpand: true, vexpand: true)
      @back_button = Widgets.icon_button("go-previous-symbolic", "Previous page") { @web.go_back }
      @forward_button = Widgets.icon_button("go-next-symbolic", "Next page") { @web.go_forward }

      build
      connect_signals(session)
    end

    def load(url : String) : Nil
      return unless WebURL.valid?(url)

      @url = url
      @status.visible = false
      @web.load_uri(url)
    end

    def stop : Nil
      @web.stop_loading
    end

    private def build : Nil
      @back_button.sensitive = false
      @forward_button.sensitive = false

      toolbar = Gtk::Box.new(Gtk::Orientation::Horizontal, 6)
      Widgets.margins(toolbar, 6)
      toolbar.append(@back_button)
      toolbar.append(@forward_button)
      toolbar.append(Widgets.icon_button("view-refresh-symbolic", "Reload page") { @web.reload })
      toolbar.append(@location)
      toolbar.append(Widgets.icon_button("web-browser-symbolic", "Open in Browser") do
        @open_external.call(current_url)
      end)

      {toolbar, @progress, @status, @web}.each { |child| @widget.append(child) }
    end

    private def connect_signals(session : WebKit::NetworkSession) : Nil
      @web.notify_signal["estimated-load-progress"].connect do
        @progress.fraction = @web.estimated_load_progress
      end
      @web.load_changed_signal.connect do |event|
        @progress.visible = event != WebKit::LoadEvent::Finished
        @back_button.sensitive = @web.can_go_back
        @forward_button.sensitive = @web.can_go_forward
        @location.label = current_url
      end
      @web.load_failed_signal.connect do |_, _, error|
        show_error("Could not load this page: #{error.message}. Use Reload or Open in Browser.")
        true
      end
      @web.web_process_terminated_signal.connect do |_|
        show_error("The page process stopped. Use Reload or Open in Browser.")
      end
      @web.decide_policy_signal.connect do |decision, kind|
        handle_policy(decision, kind)
      end
      session.download_started_signal.connect do |download|
        @open_external.call(download.request.uri)
        download.cancel
      end
      @web.permission_request_signal.connect do |request|
        request.deny
        true
      end
    end

    private def handle_policy(decision : WebKit::PolicyDecision, kind : WebKit::PolicyDecisionType) : Bool
      case kind
      when WebKit::PolicyDecisionType::NewWindowAction
        navigation = WebKit::NavigationPolicyDecision.cast(decision)
        @open_external.call(navigation.navigation_action.request.uri)
      when WebKit::PolicyDecisionType::Response
        response = WebKit::ResponsePolicyDecision.cast(decision)
        return false if response.is_mime_type_supported

        @open_external.call(response.request.uri)
      when WebKit::PolicyDecisionType::NavigationAction
        navigation = WebKit::NavigationPolicyDecision.cast(decision)
        if WebURL.valid?(navigation.navigation_action.request.uri)
          @status.visible = false
          return false
        end
      else
        return false
      end

      decision.ignore
      true
    end

    private def show_error(message : String) : Nil
      @status.label = message
      @status.visible = true
      @progress.visible = false
    end

    private def current_url : String
      @web.uri? || @url
    end
  end
end
