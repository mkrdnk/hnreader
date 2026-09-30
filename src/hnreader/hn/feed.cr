module HNReader::HN
  enum Feed
    Top
    New
    Best
    Ask
    Show
    Jobs

    def endpoint : String
      "#{self == Jobs ? "job" : to_s.downcase}stories.json"
    end
  end
end
