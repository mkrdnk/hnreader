require "spec"
require "../src/hnreader/html_content"

describe HNReader::HTMLContent do
  it "removes excluded elements recursively without class-name heuristics" do
    HNReader::HTMLContent::EXCLUDED_ELEMENTS.each do |tag|
      document = XML.parse_html("<html><body><div class=\"social shadow-md\">Useful <#{tag}>Service text</#{tag}> text</div></body></html>")
      body = document.xpath_node("//body").not_nil!

      HNReader::HTMLContent.clean(body)

      HNReader::HTMLContent.text(body).should eq("Useful text")
      body.to_xml.should contain("social shadow-md")
      body.to_xml.should_not contain("Service text")
    end
  end

  it "normalizes visible text while preserving inline word boundaries" do
    document = XML.parse_html("<html><body><p>Inter<strong>operable</strong>&nbsp; text<br>next line</p><p>Next paragraph</p><!--not text--></body></html>")
    body = document.xpath_node("//body").not_nil!

    HNReader::HTMLContent.text(body).should eq("Interoperable text next line Next paragraph")
  end

  it "preserves word separators in whitespace-only inline elements without blank links" do
    document = XML.parse_html("<html><body><p>First<span> </span>second<a href=\"/empty\">&nbsp;</a><b>third</b></p></body></html>")
    body = document.xpath_node("//body").not_nil!

    HNReader::HTMLContent.clean(body)

    HNReader::HTMLContent.text(body).should eq("First second third")
    body.xpath_nodes(".//a").should be_empty
  end

  it "keeps accessibility labels unless they are explicitly hidden" do
    document = XML.parse_html("<html><body><h1 class=\"sr-only\">Article heading</h1><a href=\"/useful\"><span class=\"sr-only\">Useful label</span></a></body></html>")
    body = document.xpath_node("//body").not_nil!

    HNReader::HTMLContent.clean(body)

    HNReader::HTMLContent.text(body).should eq("Article heading Useful label")
    body.xpath_nodes(".//h1").size.should eq(1)
    body.xpath_nodes(".//a").size.should eq(1)
  end

  it "ignores explicit hidden content even before cleaning" do
    document = XML.parse_html(<<-HTML)
      <html><body><p>Visible
        <span hidden="false">Hidden attribute</span>
        <span aria-hidden=" TRUE ">Hidden aria</span>
        <span style="color: red; DISPLAY: none !important;">Hidden display</span>
        <span style="visibility : HIDDEN">Hidden visibility</span>
        <span aria-hidden="false">Also visible</span>
        <span style="display: inline; visibility: visible">Still visible</span>
      </p></body></html>
      HTML
    body = document.xpath_node("//body").not_nil!

    HNReader::HTMLContent.text(body).should eq("Visible Also visible Still visible")
    HNReader::HTMLContent.clean(body)
    HNReader::HTMLContent.text(body).should eq("Visible Also visible Still visible")
    body.to_xml.should_not contain("Hidden")
  end

  it "drops empty links and their now-empty containers but keeps useful link labels" do
    document = XML.parse_html(<<-HTML)
      <html><body>
        <div><p><a href="/empty">&nbsp; <img src="/icon.png"><span hidden>Hidden label</span></a></p></div>
        <p><a href="/useful"><img src="/icon.png">Useful label</a></p>
      </body></html>
      HTML
    body = document.xpath_node("//body").not_nil!

    HNReader::HTMLContent.clean(body)

    body.xpath_nodes(".//div").should be_empty
    body.xpath_nodes(".//p").size.should eq(1)
    body.xpath_nodes(".//a").size.should eq(1)
    HNReader::HTMLContent.text(body).should eq("Useful label")
    body.xpath_node(".//a").not_nil!["href"].should eq("/useful")
  end
end
