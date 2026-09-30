# Inspection hooks are compiled only into the opt-in GUI test.
module HNReader::UI
  class Window
    getter feed_view, story_view, navigation, theme, client
  end

  class FeedView
    getter loader
  end

  class StoryView
    getter pages, article, discussion_box
  end

  class ArticleView
    getter web
  end
end
