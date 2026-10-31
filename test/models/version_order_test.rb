require "test_helper"

# The gem orders versions that share a timestamp by id, so a change between
# two checkpoints that tie is still reported, and diagnose has no hazard to
# warn about for these associations. VersionClock keeps the suite's
# timestamps apart for a different reason, so this test writes the tie
# directly.
class VersionOrderTest < ActiveSupport::TestCase
  test "reports a change between checkpoints that share a timestamp" do
    article = Article.create!(title: "Tie", status: "draft", body: "Body")
    comment = article.comments.create!(author: "Commenter", body: "Before")
    tag = Tag.create!(name: "Tied", description: "Attached between the checkpoints")
    before = checkpoint(article)
    Article.find(article.id).tags << tag
    comment.update!(body: "After")
    after = checkpoint(article)
    PaperTrail::Version.where("id > ?", before.id).update_all(created_at: before.created_at)
    before.reload
    after.reload

    diff = PaperTrailDiff.compare(before, after, associations: %w[comments tags])
    report = PaperTrailDiff.diagnose(before, after, associations: %w[comments tags])

    assert_equal [ comment.id ], diff.associations.fetch("comments").changed.map { _1.record.id }
    assert_equal [ tag.id ], diff.associations.fetch("tags").added.map(&:id)
    assert_not_includes report.warnings.map(&:code), :tied_version_timestamps
  end

  private

  def checkpoint(article)
    Article.transaction { Article.find(article.id).paper_trail.save_with_version }
    article.versions.reload.order(:id).last
  end
end
