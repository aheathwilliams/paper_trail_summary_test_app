require "test_helper"

class AuthorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "creates an author and attaches it to the current article" do
    before = @article.versions.last

    assert_difference -> { Author.count }, 1 do
      assert_difference -> { Authorship.count }, 1 do
        assert_difference -> { @article.versions.count }, 1 do
          post authors_url, params: {
            article_id: @article.id,
            author: {
              name: "Grace Hopper",
              bio: "Computer scientist and technical writer."
            },
            actor: "Casey Tester"
          }
        end
      end
    end

    after = @article.versions.reload.last
    authors = author_diff(@article, before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ "Grace Hopper" ], authors.added.map { |record| record.attributes.fetch("name") }
  end

  test "updates a shared author and checkpoints every linked article" do
    author = @article.authors.order(:id).first
    other_article = Article.create!(title: "Second Article", status: "draft", body: "Another article.")
    other_article.touch
    Authorship.create!(article: other_article, author: author)
    other_article.touch
    before_first = @article.versions.last
    before_second = other_article.versions.last

    assert_difference -> { @article.versions.count + other_article.versions.count }, 2 do
      patch author_url(author), params: {
        article_id: @article.id,
        author: { name: author.name, bio: "A biography edited from the demo." },
        actor: "Casey Tester"
      }
    end

    first_diff = author_diff(@article, before_first, @article.versions.reload.last)
    second_diff = author_diff(other_article, before_second, other_article.versions.reload.last)

    assert_equal 1, first_diff.changed.length
    assert_equal 1, second_diff.changed.length
  end

  private

  def author_diff(article, from, to)
    assert_includes article.versions, to
    PaperTrailDiff.compare(from, to, associations: [ :authors ])
      .associations.fetch("authors")
  end
end
