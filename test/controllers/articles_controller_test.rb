require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "creates a versioned article and initial endpoint" do
    assert_difference -> { Article.count }, 1 do
      post articles_url, params: {
        article: {
          title: "Manual Test Article",
          status: "draft",
          body: "Created through the demo form."
        },
        actor: "Casey Tester"
      }
    end

    article = Article.order(:id).last
    versions = article.versions.order(:id).to_a
    creation_diff = PaperTrailDiff.compare(versions.first, versions.last)

    assert_redirected_to root_url(article_id: article.id)
    assert_equal %w[create update], versions.map(&:event)
    assert_equal [ "Casey Tester" ], article.versions.distinct.pluck(:whodunnit)
    assert_nil creation_diff.record_presence_change.from
    assert_equal "Article", creation_diff.record_presence_change.to.type
  end

  test "updates an article and exposes its live state as an endpoint" do
    before = @article.versions.last

    assert_difference -> { @article.versions.count }, 2 do
      patch article_url(@article), params: {
        article: {
          title: "A Manually Revised Title",
          status: "archived",
          body: @article.body
        },
        actor: "Casey Tester"
      }
    end

    after = @article.versions.reload.last
    diff = PaperTrailDiff.compare(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal "A Manually Revised Title", diff.attributes.fetch("title").to
    assert_equal "archived", diff.attributes.fetch("status").to
  end
end
