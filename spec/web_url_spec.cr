require "./spec_helper"
require "../src/hnreader/web_url"

describe HNReader::WebURL do
  it "only accepts absolute HTTP and HTTPS article URLs" do
    HNReader::WebURL.valid?("https://example.com").should be_true
    ["javascript:alert(1)", "file:///etc/passwd", "https:", "//example.com"].each do |url|
      HNReader::WebURL.valid?(url).should be_false
    end
  end
end
