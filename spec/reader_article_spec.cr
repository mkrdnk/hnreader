require "spec"
require "../src/hnreader/reader_article"

describe HNReader::ReaderArticle do
  it "extracts the article and its metadata" do
    html = <<-HTML
      <html>
        <head><title>Fallback title</title><meta property="og:title" content="Reader title"></head>
        <body>
          <nav>#{"navigation " * 100}</nav>
          <article>
            <h1>Heading</h1>
            <p>#{"First paragraph with useful prose. " * 8}</p>
            <p>#{"Second paragraph with more useful prose. " * 8}</p>
          </article>
        </body>
      </html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.title.should eq("Reader title")
    article.content.should contain("First paragraph")
    article.content.should_not contain("navigation")
    article.content.should_not contain("<h1")
    article.blocks.map(&.kind).should eq([
      HNReader::ReaderArticle::BlockKind::Paragraph,
      HNReader::ReaderArticle::BlockKind::Paragraph,
    ])
  end

  it "uses a content-like container when semantic elements are absent" do
    html = <<-HTML
      <html><head><title>Plain page</title></head><body>
        <div class="sidebar">Related links and navigation</div>
        <div class="post-content">
          <p>#{"Useful article text. " * 10}</p>
          <p>#{"A detailed second paragraph. " * 10}</p>
          <p>#{"The concluding paragraph. " * 10}</p>
        </div>
      </body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.title.should eq("Plain page")
    article.content.should contain("concluding paragraph")
  end

  it "extracts simple documents with paragraphs directly in the body" do
    html = <<-HTML
      <html><head><title>Simple document</title></head><body>
        <p>#{"First body paragraph. " * 8}</p>
        <p>#{"Second body paragraph. " * 8}</p>
        <p>#{"Third body paragraph. " * 8}</p>
      </body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.title.should eq("Simple document")
    article.content.should contain("Third body paragraph")
  end

  it "preserves the article as separate readable blocks" do
    html = <<-HTML
      <html><body><article>
        <h1>Structured article</h1>
        <h2>A section</h2>
        <p>#{"Readable prose. " * 15}</p>
        <blockquote><p>A quoted paragraph.</p></blockquote>
        <ul><li>First point</li><li>Second point</li></ul>
        <pre>puts "code"</pre>
        <div class="related"><p>This should not be included.</p></div>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.blocks.map(&.kind).should eq([
      HNReader::ReaderArticle::BlockKind::Heading,
      HNReader::ReaderArticle::BlockKind::Paragraph,
      HNReader::ReaderArticle::BlockKind::Quote,
      HNReader::ReaderArticle::BlockKind::ListItem,
      HNReader::ReaderArticle::BlockKind::ListItem,
      HNReader::ReaderArticle::BlockKind::Code,
    ])
    article.blocks.map(&.html).join.should_not contain("should not be included")
  end

  it "rejects pages without enough readable content" do
    HNReader::ReaderArticle.extract("<html><body><main><p>Short.</p></main></body></html>").should be_nil
  end

  it "cleans the Firmenza list shape without losing its ordered markers or useful content" do
    html = <<-HTML
      <html><body><article>
        <h1>Public records</h1>
        <p>#{"Useful context for the following checks. " * 8}</p>
        <ol>
          <li><span aria-hidden="true">1</span><h3>Check</h3><p>See what your public record says.</p></li>
          <li><span aria-hidden="true">2</span><h3>Review</h3><p>Review the details carefully.</p></li>
        </ol>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    items = article.blocks.select(&.kind.list_item?)
    items.size.should eq(2)
    items[0].html.should start_with(%(<ol start="1">))
    items[0].html.should contain("<h3>Check</h3>")
    items[0].html.should contain("<p>See what your public record says.</p>")
    items[1].html.should start_with(%(<ol start="2">))
    article.content.should_not contain("aria-hidden")
    items.map(&.html).join.should_not contain("<span")
  end

  it "removes hidden and service descendants inside paragraphs and list items" do
    html = <<-HTML
      <html><body><article>
        <p>#{"Useful prose. " * 20}<span><span hidden>Hidden text</span>Visible words</span>
          <span style="color:red; DISPLAY : none !important">Hidden style</span>
          <span style="visibility: hidden;">Invisible text</span>
          <button>Service button</button><span class="social-share">Service share</span>
        </p>
        <ul><li>Useful item<span><span aria-hidden="true">Decoration</span></span>
          <span class="related">Related links</span><template>Template text</template>
        </li></ul>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    [article.content, article.blocks.map(&.html).join].each do |content|
      content.should contain("Visible words")
      content.should contain("Useful item")
      ["Hidden text", "Hidden style", "Invisible text", "Service button", "Service share",
       "Decoration", "Related links", "Template text"].each do |unwanted|
        content.should_not contain(unwanted)
      end
    end
  end

  it "drops empty links and blocks rather than preserving blank reader widgets" do
    html = <<-HTML
      <html><body><article>
        <p>#{"Useful prose. " * 20}<a href="/empty"> &nbsp; </a>
          <a href="/image"><img src="/icon.png"></a><a href="/useful">Useful link</a>
        </p>
        <p> &nbsp; <span hidden>Hidden</span></p>
        <ul><li><a href="/empty-item"><img src="/icon.png"></a></li><li>Useful item</li></ul>
        <div><p><a href="/empty-block"> </a></p></div>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.blocks.size.should eq(2)
    article.content.should_not contain("/empty")
    article.content.should_not contain("/image")
    article.content.should_not contain("<div")
    article.content.should contain(%(<a href="/useful">Useful link</a>))
  end

  it "cleans candidates before scoring so hidden UI cannot displace useful prose" do
    html = <<-HTML
      <html><body>
        <article><h1>UI title</h1><div hidden>#{"Hidden UI text. " * 200}</div><p>Short.</p></article>
        <main><h1>Useful title</h1><p>#{"Readable article text. " * 15}</p></main>
      </body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.title.should eq("Useful title")
    article.content.should contain("Readable article text.")
    article.content.should_not contain("UI")
  end

  it "does not mistake a shadow utility class for advertising" do
    html = <<-HTML
      <html><body><div class="post-content shadow-md">
        <p class="download-link">#{"Useful prose about a download. " * 10}</p>
      </div></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    article.content.should contain("Useful prose about a download.")
  end

  it "rejects UI-only content and text hidden inside otherwise readable blocks" do
    html = <<-HTML
      <html><body><main>
        <h1>Site interface</h1>
        <p><span hidden>#{"Hidden article text. " * 100}</span></p>
        <p><button>#{"Log in or sign up. " * 100}</button></p>
        <p><span class="related">#{"Related links. " * 100}</span></p>
        <a href="/one"> &nbsp; </a><a href="/two"><img src="/icon.png"></a>
      </main></body></html>
      HTML

    HNReader::ReaderArticle.extract(html).should be_nil
  end

  it "checks the content threshold after removing the title and hidden text" do
    [199, 200].each do |length|
      html = <<-HTML
        <html><body><article>
          <h1>#{"Long title " * 30}</h1>
          <p>#{"x" * length}<span hidden>#{"Hidden " * 100}</span></p>
        </article></body></html>
        HTML

      article = HNReader::ReaderArticle.extract(html)
      if length < HNReader::ReaderArticle::MIN_CONTENT_LENGTH
        article.should be_nil
      else
        article.should_not be_nil
      end
    end
  end

  it "rejects a long title with only an empty link for content" do
    html = <<-HTML
      <html><body><article><h1>#{"Title " * 50}</h1><p><a href="/empty"> </a></p></article></body></html>
      HTML

    HNReader::ReaderArticle.extract(html).should be_nil
  end

  it "preserves ordered list start and value across removed siblings" do
    html = <<-HTML
      <html><body><article><p>#{"Useful prose. " * 20}</p>
        <ol start="3">
          <li>Third</li><li hidden>Fourth</li><li>Fifth</li>
          <li value="10">Tenth</li><li><span hidden>Empty eleventh</span></li><li>Twelfth</li>
        </ol>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    items = article.blocks.select(&.kind.list_item?)
    items.size.should eq(4)
    items.zip([3, 5, 10, 12]).each do |item, number|
      item.html.should start_with(%(<ol start="#{number}">))
      item.html.should contain(%(<li value="#{number}">))
    end
  end

  it "preserves reversed ordered lists with implicit starts and explicit value resets" do
    html = <<-HTML
      <html><body><article><p>#{"Useful prose. " * 20}</p>
        <ol reversed><li>Fourth</li><li hidden>Third</li><li value="0">Zero</li><li>Minus one</li></ol>
        <ol reversed start="8"><li>Eighth</li><li>Seventh</li></ol>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    items = article.blocks.select(&.kind.list_item?)
    items.size.should eq(5)
    items.zip([4, 0, -1, 8, 7]).each do |item, number|
      item.html.should start_with(%(<ol start="#{number}">))
    end
  end

  it "preserves list counters across signed 32-bit boundaries without overflow" do
    html = <<-HTML
      <html><body><article><p>#{"Useful prose. " * 20}</p>
        <ol start="2147483647"><li>Maximum</li><li>Next</li></ol>
        <ol reversed start="-2147483648"><li>Minimum</li><li>Previous</li></ol>
        <ol><li value="2147483647">Maximum reset</li><li>Next after reset</li></ol>
        <ol reversed><li value="-2147483648">Minimum reset</li><li>Previous after reset</li></ol>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    items = article.blocks.select(&.kind.list_item?)
    numbers = [2147483647_i64, 2147483648_i64, -2147483648_i64, -2147483649_i64] * 2
    items.size.should eq(numbers.size)
    items.zip(numbers).each do |item, number|
      item.html.should start_with(%(<ol start="#{number}">))
      item.html.should contain(%(<li value="#{number}">))
    end
  end

  it "keeps nested lists inside their parent item and unordered items unwrapped" do
    html = <<-HTML
      <html><body><article><p>#{"Useful prose. " * 20}</p>
        <ol start="2"><li>Outer<ol start="4" reversed><li>Inner fourth</li><li>Inner third</li></ol>
          <ul><li>Nested bullet</li></ul></li><li>Next outer</li></ol>
        <ul><li>Top-level bullet</li></ul>
      </article></body></html>
      HTML

    article = HNReader::ReaderArticle.extract(html).not_nil!
    items = article.blocks.select(&.kind.list_item?)
    items.size.should eq(3)
    items[0].html.should start_with(%(<ol start="2">))
    nested = XML.parse_html(items[0].html).xpath_node("//li/ol").not_nil!
    nested["start"].should eq("4")
    nested["reversed"]?.should_not be_nil
    nested.xpath_nodes("./li").map { |item| item["value"] }.should eq(["4", "3"])
    items[0].html.should contain("<ul>")
    items[1].html.should start_with(%(<ol start="3">))
    items[2].html.should eq("<li>Top-level bullet</li>")
  end
end
