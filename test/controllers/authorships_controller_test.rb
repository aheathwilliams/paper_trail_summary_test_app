require "test_helper"

class AuthorshipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "attaches an existing author through the join model" do
    author = Author.create!(name: "Available Author", bio: "Not linked yet.")
    before = @article.versions.last

    assert_difference -> { @article.authorships.count }, 1 do
      post article_authorships_url(@article), params: {
        authorship: {
          author_id: author.id,
          role: "researcher",
          position: 3,
          credited_as: "A. Author"
        },
        actor: "Casey Tester"
      }
    end

    after = @article.versions.reload.last
    authors = author_diff(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ author.id ], authors.added.map(&:id)
    authorship = @article.authorships.reload.find_by!(author: author)
    assert_equal [ "researcher", 3, "A. Author" ],
      [ authorship.role, authorship.position, authorship.credited_as ]
  end

  test "detaches an author through the join model" do
    authorship = @article.authorships.order(:id).first
    before = @article.versions.last

    assert_difference -> { @article.authorships.count }, -1 do
      delete article_authorship_url(@article, authorship), params: { actor: "Casey Tester" }
    end

    after = @article.versions.reload.last
    authors = author_diff(before, after)

    assert_redirected_to root_url(article_id: @article.id)
    assert_equal [ authorship.author_id ], authors.removed.map(&:id)
  end

  private

  def author_diff(from, to)
    PaperTrailDiff.compare(from, to, associations: [ :authors ])
      .associations.fetch("authors")
  end
end
