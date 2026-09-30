module HNReader
  APPLICATION_ID   = "hnreader.makridenko.com"
  APPLICATION_NAME = "HN Reader"
  VERSION          = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("version:")).split(":")[1].strip }}

  GITHUB_URL  = "https://github.com/mkrdnk/hnreader"
  HN_URL      = "https://news.ycombinator.com/"
  HN_ITEM_URL = "#{HN_URL}item?id="
  AUTHOR_URL  = "https://makridenko.com/"
  HN_API_URL  = "https://hacker-news.firebaseio.com/v0"
end
