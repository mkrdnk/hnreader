require "html"
require "json"

module HNReader::HN
  class Item
    include JSON::Serializable

    getter id : Int64
    getter type : String = "story"
    getter title : String = "Untitled"
    getter text : String = ""
    getter url : String?

    @[JSON::Field(key: "by")]
    getter author : String = "[deleted]"

    getter score : Int64 = 0_i64
    getter time : Int64 = 0_i64
    getter descendants : Int64 = 0_i64
    getter kids : Array(Int64) = [] of Int64
    getter? deleted : Bool = false
    getter? dead : Bool = false

    # HN returns JSON null for missing items. Field defaults also cover nulls.
    def self.parse(body : String) : Item?
      (Item | Nil).from_json(body)
    end

    def visible? : Bool
      !deleted? && !dead?
    end

    protected def after_initialize : Nil
      @title = HTML.unescape(@title)
      @url = @url.presence
    end
  end
end
