require "xml"

module HNReader
  class ReaderArticle
    MIN_CONTENT_LENGTH = 200
    POSITIVE_HINT      = /article|body|content|entry|main|post|story/i
    NEGATIVE_HINT      = /ad-|advert|comment|footer|header|menu|nav|promo|related|share|sidebar|social/i
    PARSER_OPTIONS     = XML::HTMLParserOptions::RECOVER |
                         XML::HTMLParserOptions::NOERROR |
                         XML::HTMLParserOptions::NOWARNING |
                         XML::HTMLParserOptions::NONET

    enum BlockKind
      Paragraph
      Heading
      Quote
      Code
      ListItem
      TableRow
    end

    record Block, kind : BlockKind, html : String

    getter title : String
    getter content : String
    getter blocks : Array(Block)

    def initialize(@title : String, @content : String, @blocks : Array(Block))
    end

    def self.extract(html : String) : ReaderArticle?
      return if html.empty?

      document = XML.parse_html(html, PARSER_OPTIONS)
      candidate = primary_candidate(document) || fallback_candidate(document) || body_candidate(document)
      return unless candidate
      return if text(candidate).size < MIN_CONTENT_LENGTH

      heading = candidate.xpath_node(".//h1")
      title = metadata(document, "//meta[@property='og:title']/@content") ||
              node_text(heading) ||
              node_text(document.xpath_node("//title")) ||
              "Article"
      heading.try(&.unlink)
      content = candidate.to_xml
      blocks = [] of Block
      collect_blocks(candidate, blocks)
      return if blocks.empty?

      ReaderArticle.new(title, content, blocks)
    rescue XML::Error
      nil
    end

    private def self.primary_candidate(document : XML::Node) : XML::Node?
      candidates = document.xpath_nodes("//article | //main | //*[@role='main']").select do |node|
        text(node).size >= MIN_CONTENT_LENGTH
      end
      candidates.max_by? { |node| score(node) }
    end

    private def self.fallback_candidate(document : XML::Node) : XML::Node?
      candidates = document.xpath_nodes("//div | //section").select do |node|
        hint = "#{node["id"]?} #{node["class"]?}"
        paragraphs = node.xpath_nodes(".//p").size
        (hint.matches?(POSITIVE_HINT) || paragraphs >= 3) &&
          !hint.matches?(NEGATIVE_HINT) &&
          text(node).size >= MIN_CONTENT_LENGTH
      end
      candidates.max_by? { |node| score(node) }
    end

    private def self.body_candidate(document : XML::Node) : XML::Node?
      body = document.xpath_node("//body")
      return unless body
      return if body.xpath_nodes(".//p").size < 3
      return if text(body).size < MIN_CONTENT_LENGTH
      return if link_text_length(body) * 2 >= text(body).size

      body
    end

    private def self.score(node : XML::Node) : Int32
      hint = "#{node["id"]?} #{node["class"]?}"
      value = text(node).size + node.xpath_nodes(".//p").size * 100
      value += 1_000 if node.name.downcase == "article"
      value += 500 if hint.matches?(POSITIVE_HINT)
      value -= 2_000 if hint.matches?(NEGATIVE_HINT)
      value - link_text_length(node)
    end

    private def self.link_text_length(node : XML::Node) : Int32
      node.xpath_nodes(".//a").sum { |link| text(link).size }
    end

    private def self.collect_blocks(node : XML::Node, blocks : Array(Block)) : Nil
      return unless node.element?

      name = node.name.downcase
      return if {"script", "style", "iframe", "object", "nav", "header", "footer", "aside",
                 "form", "button", "noscript", "svg", "canvas"}.includes?(name)
      hint = "#{node["id"]?} #{node["class"]?}"
      return if hint.matches?(NEGATIVE_HINT)

      kind = case name
             when "p"                                then BlockKind::Paragraph
             when "h1", "h2", "h3", "h4", "h5", "h6" then BlockKind::Heading
             when "blockquote"                       then BlockKind::Quote
             when "pre"                              then BlockKind::Code
             when "li"                               then BlockKind::ListItem
             when "tr"                               then BlockKind::TableRow
             end
      if kind
        blocks << Block.new(kind, node.to_xml) unless text(node).empty?
        return
      end

      children = node.children.select(&.element?)
      descendants = node.xpath_nodes(".//p | .//h1 | .//h2 | .//h3 | .//h4 | .//h5 | .//h6 | .//blockquote | .//pre | .//li | .//tr")
      if descendants.empty?
        blocks << Block.new(BlockKind::Paragraph, node.to_xml) unless text(node).empty?
      else
        children.each { |child| collect_blocks(child, blocks) }
      end
    end

    private def self.metadata(document : XML::Node, xpath : String) : String?
      document.xpath_node(xpath).try { |node| clean(node.content).presence }
    end

    private def self.node_text(node : XML::Node?) : String?
      node.try { |value| clean(value.content).presence }
    end

    private def self.text(node : XML::Node) : String
      clean(node.content)
    end

    private def self.clean(value : String) : String
      value.gsub(/\s+/, " ").strip
    end
  end
end
