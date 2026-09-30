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
end
