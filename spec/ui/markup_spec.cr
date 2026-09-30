require "../spec_helper"
require "../../src/hnreader/ui/markup"

describe HNReader::UI::Markup do
  it "preserves basic formatting, entities and code" do
    html = "Hello &amp; &lt;world&gt;<p><i>italic</i> <b>bold</b><pre>x &lt; y</pre>"
    expected = "Hello &amp; &lt;world&gt;\n\n<i>italic</i> <b>bold</b>\n<tt>x &lt; y</tt>"

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
end
