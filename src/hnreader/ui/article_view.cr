require "../preferences"
require "../reader_article"
require "./formatting"
require "./widgets"

GICrystal.require("WebKit", "6.0")

module HNReader::UI
  class ArticleView
    getter widget = Gtk::Box.new(Gtk::Orientation::Vertical, 0)

    @web : WebKit::WebView
    @pages = Gtk::Stack.new(hexpand: true, vexpand: true)
    @reader_content = Gtk::Box.new(Gtk::Orientation::Vertical, 18)
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
    @reader_button : Gtk::ToggleButton
    @reader_article : ReaderArticle?
    @main_resource : WebKit::WebResource?
    @url = ""
    @generation = 0_u64
    @document_ready = false
    @extracting = false

    def initialize(@preferences : Preferences, &@open_external : String -> Nil)
      # Keep website state in memory, without creating a browser profile.
      session = WebKit::NetworkSession.new_ephemeral
      @web = WebKit::WebView.new(network_session: session, hexpand: true, vexpand: true)
      @back_button = Widgets.icon_button("go-previous-symbolic", "Previous page") { @web.go_back }
      @forward_button = Widgets.icon_button("go-next-symbolic", "Next page") { @web.go_forward }
      @reader_button = Gtk::ToggleButton.new(
        label: "Reader",
        tooltip_text: "Toggle reader mode for this article",
        active: @preferences.reader_mode?,
      )

      build
      connect_signals(session)
    end

    def load(url : String) : Nil
      return unless WebURL.valid?(url)

      @url = url
      @status.visible = false
      if @reader_button.active?
        show_reader_loading
      else
        @pages.visible_child_name = "website"
      end
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
      toolbar.append(@reader_button)
      toolbar.append(@location)
      toolbar.append(Widgets.icon_button("web-browser-symbolic", "Open in Browser") do
        @open_external.call(current_url)
      end)

      reader = Gtk::ScrolledWindow.new(
        hscrollbar_policy: Gtk::PolicyType::Never,
        child: Adw::Clamp.new(maximum_size: 760, child: @reader_content),
      )
      @pages.add_named(reader, "reader")
      @pages.add_named(@web, "website")
      @pages.visible_child_name = @reader_button.active? ? "reader" : "website"
      {toolbar, @progress, @status, @pages}.each { |child| @widget.append(child) }
    end

    private def connect_signals(session : WebKit::NetworkSession) : Nil
      @reader_button.toggled_signal.connect do
        if @reader_button.active?
          show_reader
        else
          @pages.visible_child_name = "website"
        end
      end
      @web.notify_signal["estimated-load-progress"].connect do
        @progress.fraction = @web.estimated_load_progress
      end
      @web.load_changed_signal.connect do |event|
        begin_navigation if event == WebKit::LoadEvent::Started
        watch_main_resource if event == WebKit::LoadEvent::Committed
        @progress.visible = event != WebKit::LoadEvent::Finished
        @back_button.sensitive = @web.can_go_back
        @forward_button.sensitive = @web.can_go_forward
        @location.label = current_url
        if event == WebKit::LoadEvent::Finished && !@document_ready
          @main_resource ||= @web.main_resource
          @document_ready = true
          extract_reader if @reader_button.active?
        end
      end
      @web.load_failed_signal.connect do |_, _, error|
        @reader_button.active = false
        @pages.visible_child_name = "website"
        show_error("Could not load this page: #{error.message}. Use Reload or Open in Browser.")
        true
      end
      @web.web_process_terminated_signal.connect do |_|
        @reader_button.active = false
        @pages.visible_child_name = "website"
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

    private def begin_navigation : Nil
      @generation &+= 1
      @reader_article = nil
      @main_resource = nil
      @document_ready = false
      @extracting = false
      @status.visible = false
      show_reader_loading if @reader_button.active?
    end

    private def watch_main_resource : Nil
      generation = @generation
      resource = @web.main_resource
      @main_resource = resource
      resource.finished_signal.connect do
        next unless generation == @generation

        @document_ready = true
        extract_reader if @reader_button.active?
      end
    end

    private def show_reader : Nil
      if article = @reader_article
        render_reader(article)
      elsif @document_ready
        show_reader_loading
        extract_reader
      else
        show_reader_loading
      end
    end

    private def show_reader_loading : Nil
      Widgets.clear(@reader_content)
      Widgets.margins(@reader_content, 24)
      spinner = Gtk::Spinner.new(spinning: true, halign: Gtk::Align::Center)
      @reader_content.append(spinner)
      @reader_content.append(Gtk::Label.new(label: "Preparing reading view…", css_classes: ["dim-label"]))
      @pages.visible_child_name = "reader"
    end

    private def extract_reader : Nil
      return if @extracting || !@document_ready
      return unless resource = @main_resource

      @extracting = true
      generation = @generation
      resource.data(nil) do |source, result|
        begin
          bytes = WebKit::WebResource.cast(source).data_finish(result)
          html = String.new(bytes)
          article = ReaderArticle.extract(html)
          next unless generation == @generation

          @extracting = false
          if article
            @reader_article = article
            render_reader(article) if @reader_button.active?
          else
            reader_unavailable
          end
        rescue error : GLib::Error
          next unless generation == @generation

          @extracting = false
          reader_unavailable
        end
      end
    end

    private def render_reader(article : ReaderArticle) : Nil
      Widgets.clear(@reader_content)
      Widgets.margins(@reader_content, 24)
      title = Widgets.label(article.title, "title-1")
      title.selectable = true
      @reader_content.append(title)
      @reader_content.append(Widgets.label(Formatting.domain(current_url), "dim-label"))
      article.blocks.each { |block| append_reader_block(block) }
      @pages.visible_child_name = "reader"
      @progress.visible = false
      @status.visible = false
    end

    private def append_reader_block(block : ReaderArticle::Block) : Nil
      label = Widgets.rich_text(block.html, current_url) { |url| load(url) }
      case block.kind
      when .heading?
        label.add_css_class("reader-heading")
        label.margin_top = 12
      when .quote?
        label.add_css_class("reader-quote")
      when .code?
        label.add_css_class("reader-code")
      when .list_item?
        label.add_css_class("reader-list-item")
      else
        label.add_css_class("reader-body")
      end
      @reader_content.append(label)
    end

    private def reader_unavailable : Nil
      return unless @reader_button.active?

      @reader_button.active = false
      @pages.visible_child_name = "website"
      @status.label = "Reading view is not available for this page. Showing the website instead."
      @status.visible = true
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
