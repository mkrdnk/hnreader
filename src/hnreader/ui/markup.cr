require "html"
require "xml"
require "../web_url"
require "../html_content"

module HNReader::UI
  module Markup
    extend self

    PARSER_OPTIONS = XML::HTMLParserOptions::RECOVER |
                     XML::HTMLParserOptions::NOERROR |
                     XML::HTMLParserOptions::NOWARNING |
                     XML::HTMLParserOptions::NONET

    # Parse HTML, never pass remote HTML directly to Pango markup.
    def render(html : String, base_url : String? = nil) : String
      return "" if html.empty?

      doc = XML.parse_html("<html><body>#{html}</body></html>", PARSER_OPTIONS)
      body = doc.xpath_node("//body")
      return HTML.escape(html) unless body

      HTMLContent.clean(body)
      Renderer.new(base_url).render(body.children)
    rescue XML::Error
      HTML.escape(html)
    end

    # Keep HTML whitespace pending until visible text arrives. This places spaces
    # outside link/style tags and avoids empty formatting around indentation.
    private class Renderer
      private class Tag
        getter opening : String
        getter closing : String
        property? emitted = false

        def initialize(@opening : String, @closing : String)
        end
      end

      @io = String::Builder.new
      @tags = [] of Tag
      @pending_space = false
      @pending_breaks = 0
      @has_content = false
      getter? starts_with_list = false

      def initialize(@base_url : String?, @compact : Bool = false, @list_depth : Int32 = 0)
      end

      def render(nodes) : String
        nodes.each { |node| append(node) }
        @io.to_s
      end

      private def append(node : XML::Node, preformatted : Bool = false) : Nil
        if node.text?
          if preformatted
            write(HTML.escape(node.content)) unless node.content.empty?
          else
            node.content.scan(/[ \t\r\n\f]+|[^ \t\r\n\f]+/) do |match|
              if match[0].matches?(/\A[ \t\r\n\f]/)
                @pending_space = true
              else
                write(HTML.escape(match[0]))
              end
            end
          end
          return
        end
        return unless node.element?

        case node.name.downcase
        when "p", "div", "section"
          block { children(node, preformatted) }
        when "h1", "h2", "h3", "h4", "h5", "h6"
          block { tag("<b>", "</b>") { children(node, preformatted) } }
        when "ul", "ol"
          list(node)
        when "li"
          list_item(node, "• ")
        when "blockquote"
          block { tag("<i>", "</i>") { children(node, preformatted) } }
        when "br"
          if preformatted
            write("\n")
          else
            @pending_breaks += 1
            @pending_space = false
          end
        when "i", "em"
          tag("<i>", "</i>") { children(node, preformatted) }
        when "b", "strong"
          tag("<b>", "</b>") { children(node, preformatted) }
        when "pre"
          block(1) { tag("<tt>", "</tt>") { children(node, true) } }
        when "code"
          tag("<tt>", "</tt>") { children(node, preformatted) }
        when "a"
          url = resolve_url(node["href"]? || "")
          if WebURL.valid?(url)
            tag(%(<a href="#{HTML.escape(url)}">), "</a>") { children(node, preformatted) }
          else
            children(node, preformatted)
          end
        else
          children(node, preformatted)
        end
      end

      private def children(node : XML::Node, preformatted : Bool) : Nil
        node.children.each { |child| append(child, preformatted) }
      end

      private def block(breaks : Int32 = @compact ? 1 : 2, &) : Nil
        separate(breaks)
        yield
        separate(breaks)
      end

      private def separate(breaks : Int32) : Nil
        @pending_breaks = Math.max(@pending_breaks, breaks)
        @pending_space = false
      end

      private def tag(opening : String, closing : String, &) : Nil
        current = Tag.new(opening, closing)
        @tags << current
        yield
        @tags.pop
        @io << closing if current.emitted?
      end

      private def write(markup : String) : Nil
        if @has_content
          if @pending_breaks > 0
            @io << "\n" * @pending_breaks
          elsif @pending_space
            @io << ' '
          end
        end
        @pending_breaks = 0
        @pending_space = false
        @tags.each do |current|
          unless current.emitted?
            @io << current.opening
            current.emitted = true
          end
        end
        @io << markup
        @has_content = true
      end

      private def list(node : XML::Node) : Nil
        ordered = node.name.downcase == "ol"
        step = node["reversed"]? ? -1 : 1
        number = (node["start"]?.try(&.to_i64?) ||
                  (step == -1 ? node.children.count { |child| child.element? && child.name == "li" } : 1)).to_i64
        node.children.each do |child|
          next unless child.element?

          if child.name.downcase == "li"
            number = child["value"]?.try(&.to_i64?) || number if ordered
            list_item(child, ordered ? "#{number}. " : "• ")
            unless (step == 1 && number == Int64::MAX) || (step == -1 && number == Int64::MIN)
              number += step
            end
          else
            append(child)
          end
        end
      end

      private def list_item(node : XML::Node, marker : String) : Nil
        renderer = Renderer.new(@base_url, compact: true, list_depth: @list_depth + 1)
        content = renderer.render(node.children)
        return if content.empty?

        @starts_with_list = true unless @has_content
        marker = "#{marker.rstrip}\n" if renderer.starts_with_list?
        block(1) { write("#{"  " * @list_depth}#{marker}#{content}") }
      end

      private def resolve_url(url : String) : String
        return url if url.empty? || WebURL.valid?(url)
        return url unless base_url = @base_url

        URI.parse(base_url).resolve(url).to_s
      rescue URI::Error
        url
      end
    end
  end
end
