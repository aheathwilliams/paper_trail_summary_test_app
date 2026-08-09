require "test_helper"

class RepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
    @comment = @article.comments.order(:id).first
  end

  test "creates a reply at a nested association endpoint" do
    before = @article.versions.last

    post article_comment_replies_url(@article, @comment), params: {
      reply: { responder: "Casey", body: "Nested manually." },
      actor: "Casey Tester"
    }

    replies = reply_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal 1, replies.added.length
    assert_equal "Casey", replies.added.first.attributes.fetch("responder")
  end

  test "updates a reply at a nested association endpoint" do
    reply = @comment.replies.order(:id).first
    before = @article.versions.last

    patch article_comment_reply_url(@article, @comment, reply), params: {
      reply: { responder: reply.responder, body: "Nested edit." },
      actor: "Casey Tester"
    }

    replies = reply_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal "Nested edit.", replies.changed.first.attributes.fetch("body").to
  end

  test "removes a reply at a nested association endpoint" do
    reply = @comment.replies.order(:id).first
    before = @article.versions.last

    delete article_comment_reply_url(@article, @comment, reply), params: { actor: "Casey Tester" }

    replies = reply_diff(before, @article.versions.reload.last)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ reply.id ], replies.removed.map(&:id)
  end

  private

  def reply_diff(from, to)
    comments = PaperTrailDiff.compare(from, to, associations: [ "comments.replies" ])
      .associations.fetch("comments")
    comment = comments.changed.find { |change| change.record.fetch(:id) == @comment.id }
    comment.associations.fetch("replies")
  end
end
