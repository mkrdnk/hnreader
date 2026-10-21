require "xml"

module HNReader::HTMLContent
  extend self

  EXCLUDED_ELEMENTS = {"script", "style", "iframe", "object", "nav", "header", "footer",
                       "aside", "form", "button", "noscript", "svg", "canvas", "template"}
  BLOCK_ELEMENTS = {"article", "main", "section", "div", "p", "h1", "h2", "h3", "h4",
                    "h5", "h6", "blockquote", "pre", "ul", "ol", "li", "dl", "dt", "dd",
                    "table", "thead", "tbody", "tfoot", "tr", "td", "th", "figure", "figcaption"}
  HIDDEN_STYLE = /(?:\A|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden)\s*(?:!\s*important\s*)?(?:;|\z)/i

  # The passed node remains attached; only its descendants are removed.
  def clean(node : XML::Node) : Nil
    node.children.to_a.each do |child|
      next unless child.element?

      if excluded?(child)
        child.unlink
        next
      end

      clean(child)
      name = child.name.downcase
      if (BLOCK_ELEMENTS.includes?(name) || name == "a") && text(child).empty?
        if name == "a" && !child.content.empty?
          # Keep visible whitespace between adjacent words, but not an empty link.
          child.name = "span"
          child.delete("href")
        else
          child.unlink
        end
      end
    end
  end

  def text(node : XML::Node) : String
    String.build { |io| append_text(node, io) }.gsub(/[\s\x{00a0}]+/, " ").strip
  end

  private def excluded?(node : XML::Node) : Bool
    EXCLUDED_ELEMENTS.includes?(node.name.downcase) ||
      !node["hidden"]?.nil? ||
      node["aria-hidden"]?.try(&.strip.downcase) == "true" ||
      (node["style"]? || "").matches?(HIDDEN_STYLE)
  end

  private def append_text(node : XML::Node, io : IO) : Nil
    if node.text?
      io << node.content
      return
    end
    return unless node.element? || node.document?
    return if node.element? && excluded?(node)

    boundary = BLOCK_ELEMENTS.includes?(node.name.downcase) || node.name.downcase == "br"
    io << ' ' if boundary
    node.children.each { |child| append_text(child, io) }
    io << ' ' if boundary
  end
end
