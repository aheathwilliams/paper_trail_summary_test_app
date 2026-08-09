require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "creates a comment and an article association endpoint" do
    before = @article.versions.last

    assert_difference -> { @article.comments.count }, 1 do
      assert_difference -> { @article.versions.count }, 1 do
        post article_comments_url(@article), params: {
          comment: { author: "Casey", body: "Created manually." },
          actor: "Casey Tester"
        }
      end
    end

    after = @article.versions.reload.last
    comments = comment_diff(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal 1, comments.added.length
    assert_equal "Casey", comments.added.first.attributes.fetch("author")
  end

  test "updates a comment and an article association endpoint" do
    comment = @article.comments.order(:id).first
    before = @article.versions.last

    patch article_comment_url(@article, comment), params: {
      comment: { author: comment.author, body: "Edited manually." },
      actor: "Casey Tester"
    }

    after = @article.versions.reload.last
    comments = comment_diff(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal 1, comments.changed.length
    assert_equal "Edited manually.", comments.changed.first.attributes.fetch("body").to
  end

  test "removes a comment and an article association endpoint" do
    comment = @article.comments.order(:id).first
    before = @article.versions.last

    delete article_comment_url(@article, comment), params: { actor: "Casey Tester" }

    after = @article.versions.reload.last
    comments = comment_diff(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ comment.id ], comments.removed.map(&:id)
  end

  private

  def comment_diff(from, to)
    PaperTrailDiff.compare(from, to, associations: [ :comments ])
      .associations.fetch("comments")
  end
end
