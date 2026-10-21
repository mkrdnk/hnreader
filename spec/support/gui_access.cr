# Inspection hooks are compiled only into the opt-in GUI test.
module HNReader::UI
  class Window
    getter feed_view, story_view, navigation, theme, client, preferences, history
  end

  class FeedView
    getter loader, list, rendered_ids
  end

  class StoryView
    getter pages, article, article_box, discussion_box, discussion_scroll, comments, discussion_position
  end

  class CommentsView
    getter more
  end

  class ReadingPosition
    getter? restored
  end

  class ArticleView
    getter web, pages, reader_content, reader_button, reader_scroll, reader_position
  end
end
