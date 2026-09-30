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
    def render(html : String) : String
      return "" if html.empty?

      doc = XML.parse_html("<html><body>#{html}</body></html>", PARSER_OPTIONS)
      body = doc.xpath_node("//body")
      return HTML.escape(html) unless body

      String.build { |io| body.children.each { |node| append(node, io) } }.strip
    rescue XML::Error
      HTML.escape(html)
    end

    private def append(node : XML::Node, io : IO) : Nil
      if node.text?
        io << HTML.escape(node.content)
        return
      end
      return unless node.element?

      case node.name.downcase
      when "script", "style", "iframe", "object"
        return
      when "p", "div"
        io << "\n\n"
        children(node, io)
      when "br"
        io << '\n'
      when "i", "em"
        io << "<i>"
        children(node, io)
        io << "</i>"
      when "b", "strong"
        io << "<b>"
        children(node, io)
        io << "</b>"
      when "pre", "code"
        io << "\n" if node.name == "pre"
        io << "<tt>"
        children(node, io)
        io << "</tt>"
      when "a"
        url = node["href"]? || ""
        if WebURL.valid?(url)
          io << "<a href=\"#{HTML.escape(url)}\">"
          children(node, io)
          io << "</a>"
        else
          children(node, io)
        end
      else
        children(node, io)
      end
    end

    private def children(node : XML::Node, io : IO) : Nil
      node.children.each { |child| append(child, io) }
    end
  end
end
