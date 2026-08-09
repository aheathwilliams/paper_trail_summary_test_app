require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "creates and attaches a tag at a HABTM endpoint" do
    before = @article.versions.last

    post tags_url, params: {
      article_id: @article.id,
      tag: { name: "Manual", description: "Created manually." },
      actor: "Casey Tester"
    }

    tags = tag_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal :has_and_belongs_to_many, tags.kind
    assert_equal "Manual", tags.added.first.attributes.fetch("name")
  end

  test "updates a tag at a HABTM endpoint" do
    tag = @article.tags.order(:id).first
    before = @article.versions.last

    patch tag_url(tag), params: {
      article_id: @article.id,
      tag: { name: tag.name, description: "Updated manually." },
      actor: "Casey Tester"
    }

    tags = tag_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal "Updated manually.", tags.changed.first.attributes.fetch("description").to
  end

  private

  def tag_diff(from, to)
    PaperTrailDiff.compare(from, to, associations: [ :tags ]).associations.fetch("tags")
  end
end
