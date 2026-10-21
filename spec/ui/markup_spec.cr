require "../spec_helper"
require "../../src/hnreader/ui/markup"
require "../../src/hnreader/reader_article"

describe HNReader::UI::Markup do
  it "preserves basic formatting, entities and code" do
    html = "Hello &amp; &lt;world&gt;<p><i>italic</i> <b>bold</b><pre>x &lt; y</pre>"
    expected = "Hello &amp; &lt;world&gt;\n\n<i>italic</i> <b>bold</b>\n\n<tt>x &lt; y</tt>"

    HNReader::UI::Markup.render(html).should eq(expected)
  end

  it "escapes links and strips active content and unsafe schemes" do
    html = %(<a href="https://example.org/?a=1&amp;b=2">link</a>) +
           %(<script>bad()</script><a href="javascript:bad()">text</a>) +
           %(<span foreground="red">plain</span>)
    result = HNReader::UI::Markup.render(html)
    result.should eq(%(<a href="https://example.org/?a=1&amp;b=2">link</a>textplain))
  end

  it "recovers from malformed HTML without exposing Pango tags" do
    result = HNReader::UI::Markup.render("<p>Hello <i>there &amp; <span size='99999'>friend")
    result.should contain("Hello")
    result.should contain("&amp;")
    result.should_not contain("size=")
  end

  it "resolves relative links and removes page chrome" do
    html = %(<header>Site header</header><article><h2>Section</h2>) +
           %(<p>Read <a href="/more">more</a>.</p><ul><li>First</li><li>Second</li></ul></article>) +
           %(<footer>Site footer</footer>)
    result = HNReader::UI::Markup.render(html, "https://example.org/posts/article")

    result.should contain("<b>Section</b>")
    result.should contain(%(<a href="https://example.org/more">more</a>))
    result.should contain("• First")
    result.should_not contain("Site header")
    result.should_not contain("Site footer")
  end

  it "collapses source indentation without joining words across inline tags" do
    html = <<-HTML
      <p>
        Read <strong> this
          important </strong> text <em> carefully </em>.
      </p>
      <p>Next\t paragraph.</p>
      HTML

    HNReader::UI::Markup.render(html).should eq(
      "Read <b>this important</b> text <i>carefully</i> .\n\nNext paragraph."
    )
    HNReader::UI::Markup.render("one<span>two</span>three").should eq("onetwothree")
    HNReader::UI::Markup.render("one&nbsp; two").should eq("one\u00a0 two")
  end

  it "keeps spaces outside links and drops links without visible text" do
    html = <<-HTML
      <p><a href="/empty">
        <svg><title>Icon</title></svg>
      </a><a href="/image"><img src="photo.jpg"></a>
      <a href="/post">
        Go to vintagecomputing
      </a> now.</p>
      HTML

    HNReader::UI::Markup.render(html, "https://example.org").should eq(
      %(<a href="https://example.org/post">Go to vintagecomputing</a> now.)
    )
  end

  it "renders Firmenza steps as compact numbered items without decorative numbers" do
    html = <<-HTML
      <ol>
        <li>
          <span aria-hidden="true">1</span>
          <h3>Check</h3>
          <p>See what your public record says.</p>
        </li>
        <li>
          <span aria-hidden="true">2</span>
          <h3>Watch</h3>
          <p>An email before it expires.</p>
        </li>
      </ol>
      HTML

    HNReader::UI::Markup.render(html).should eq(
      "1. <b>Check</b>\nSee what your public record says.\n2. <b>Watch</b>\nAn email before it expires."
    )
  end

  it "honors ordered list starts, item values and reversed numbering" do
    html = "<ol start='4'><li>Four</li><li value='9'>Nine</li><li>Ten</li></ol>" +
           "<ol reversed><li>Two</li><li>One</li></ol>"
    HNReader::UI::Markup.render(html).should eq("4. Four\n9. Nine\n10. Ten\n2. Two\n1. One")
  end

  it "preserves nested lists and separates text after block elements" do
    html = "<ul><li>Parent<ul><li>Child</li></ul>After</li><li>Next</li></ul>" +
           "<div>Block</div>Following text"
    HNReader::UI::Markup.render(html).should eq(
      "• Parent\n  • Child\nAfter\n• Next\n\nBlock\n\nFollowing text"
    )
  end

  it "puts a leading nested list on its own line" do
    html = "<ul><li><ul><li>Child</li></ul></li></ul>"
    HNReader::UI::Markup.render(html).should eq("•\n  • Child")
  end

  it "does not overflow at the limits of HTML list ordinals" do
    html = "<ol start='2147483647'><li>Maximum</li><li>Next</li></ol>" +
           "<ol reversed><li value='-2147483648'>Minimum</li><li>Next</li></ol>"
    HNReader::UI::Markup.render(html).should eq(
      "2147483647. Maximum\n2147483648. Next\n-2147483648. Minimum\n-2147483649. Next"
    )
    HNReader::UI::Markup.render("<ol start='#{Int64::MAX}'><li>One</li></ol>").should eq("#{Int64::MAX}. One")
    HNReader::UI::Markup.render("<ol start='#{Int64::MIN}' reversed><li>One</li></ol>").should eq("#{Int64::MIN}. One")
  end

  it "preserves code indentation and line endings inside pre only" do
    html = "<pre><code>  if x &lt; y\n    puts <span>\"yes\"</span>\n\n  end\n</code></pre>" +
           "<p>  Normal\n text </p><code>inline   code</code>"
    HNReader::UI::Markup.render(html).should eq(
      "<tt><tt>  if x &lt; y\n    puts &quot;yes&quot;\n\n  end\n</tt></tt>\n\nNormal text\n\n<tt>inline code</tt>"
    )
  end

  it "preserves leading and trailing explicit breaks inside pre" do
    HNReader::UI::Markup.render("<pre><br>a<br></pre>").should eq("<tt>\na\n</tt>")
  end

  it "preserves explicit line breaks without exposing empty formatting" do
    html = "<p>First<br><br><b>Second</b></p><p><i> \n </i>Third</p>"
    HNReader::UI::Markup.render(html).should eq("First\n\n<b>Second</b>\n\nThird")
  end

  it "removes hidden descendants inside formatted content" do
    html = "<p>Visible <b><span hidden>hidden</span>bold</b>" +
           "<span style='display: none'>noise</span>" +
           "<span aria-hidden='true'>decoration</span>.</p>"
    HNReader::UI::Markup.render(html).should eq("Visible <b>bold</b>.")
  end

  it "renders extracted list blocks without serialization whitespace or lost numbering" do
    html = <<-HTML
      <article>
        <h1>Reading steps</h1>
        <p>#{"Useful prose for a complete article. " * 10}</p>
        <ol>
          <li><span aria-hidden="true">1</span><h3>Check</h3><p>See what your public record says.</p></li>
          <li><span aria-hidden="true">2</span><h3>Watch</h3><p>An email before it expires.</p></li>
        </ol>
        <p><a href="/empty"> <svg><title>Icon</title></svg> </a></p>
        <pre><code>  first line
          second line
      </code></pre>
      </article>
      HTML
    article = HNReader::ReaderArticle.extract(html).not_nil!
    rendered = article.blocks.map { |block| HNReader::UI::Markup.render(block.html, "https://example.org") }

    rendered.size.should eq(4)
    rendered[1].should eq("1. <b>Check</b>\nSee what your public record says.")
    rendered[2].should eq("2. <b>Watch</b>\nAn email before it expires.")
    rendered[3].should eq("<tt><tt>  first line\n    second line\n</tt></tt>")
  end

  it "preserves list ordinals beyond Int32 when rendering extracted blocks" do
    html = "<article><p>#{"Useful prose. " * 20}</p>" +
           "<ol start='2147483647'><li>Maximum</li><li>Next</li></ol></article>"
    article = HNReader::ReaderArticle.extract(html).not_nil!
    rendered = article.blocks.map { |block| HNReader::UI::Markup.render(block.html) }
    rendered[1].should eq("2147483647. Maximum")
    rendered[2].should eq("2147483648. Next")
  end
end
