require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "tracks direct many-to-many article membership" do
    tag = tags(:one)

    assert_includes tag.articles, articles(:one)
    assert_respond_to tag, :versions
  end
end
