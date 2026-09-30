require "html"
require "xml"
require "../web_url"

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

      String.build { |io| body.children.each { |node| append(node, io, base_url) } }.strip
    rescue XML::Error
      HTML.escape(html)
    end

    private def append(node : XML::Node, io : IO, base_url : String?) : Nil
      if node.text?
        io << HTML.escape(node.content)
        return
      end
      return unless node.element?

      case node.name.downcase
      when "script", "style", "iframe", "object", "nav", "header", "footer", "aside",
           "form", "button", "noscript", "svg", "canvas"
        return
      when "p", "div"
        io << "\n\n"
        children(node, io, base_url)
      when "h1", "h2", "h3", "h4", "h5", "h6"
        io << "\n\n<b>"
        children(node, io, base_url)
        io << "</b>"
      when "li"
        io << "\n• "
        children(node, io, base_url)
      when "blockquote"
        io << "\n\n<i>"
        children(node, io, base_url)
        io << "</i>"
      when "br"
        io << '\n'
      when "i", "em"
        io << "<i>"
        children(node, io, base_url)
        io << "</i>"
      when "b", "strong"
        io << "<b>"
        children(node, io, base_url)
        io << "</b>"
      when "pre", "code"
        io << "\n" if node.name == "pre"
        io << "<tt>"
        children(node, io, base_url)
        io << "</tt>"
      when "a"
        url = resolve_url(node["href"]? || "", base_url)
        if WebURL.valid?(url)
          io << "<a href=\"#{HTML.escape(url)}\">"
          children(node, io, base_url)
          io << "</a>"
        else
          children(node, io, base_url)
        end
      else
        children(node, io, base_url)
      end
    end

    private def children(node : XML::Node, io : IO, base_url : String?) : Nil
      node.children.each { |child| append(child, io, base_url) }
    end

    private def resolve_url(url : String, base_url : String?) : String
      return url if url.empty? || WebURL.valid?(url)
      return url unless base_url

      URI.parse(base_url).resolve(url).to_s
    rescue URI::Error
      url
    end
  end
end
