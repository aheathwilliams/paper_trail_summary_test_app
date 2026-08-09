require "test_helper"

class TaggingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "attaches an existing tag at a HABTM endpoint" do
    tag = Tag.where.not(id: @article.tag_ids).first
    before = @article.versions.last

    post article_taggings_url(@article), params: {
      tagging: { tag_id: tag.id },
      actor: "Casey Tester"
    }

    tags = tag_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ tag.id ], tags.added.map(&:id)
  end

  test "detaches a tag at a HABTM endpoint" do
    tag = @article.tags.order(:id).first
    before = @article.versions.last

    delete article_tagging_url(@article, tag), params: { actor: "Casey Tester" }

    tags = tag_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ tag.id ], tags.removed.map(&:id)
  end

  private

  def tag_diff(from, to)
    PaperTrailDiff.compare(from, to, associations: [ :tags ]).associations.fetch("tags")
  end
end
