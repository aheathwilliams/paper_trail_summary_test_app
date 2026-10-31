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

  # Membership is recorded only at article versions, so the controller saves a
  # checkpoint on each side of the change and the step between them is the
  # actor's. With only the checkpoint after it, the previous version's author
  # was credited.
  test "credits the person who attached or detached a tag" do
    tag = Tag.where.not(id: @article.tag_ids).first
    before = latest_version

    post article_taggings_url(@article), params: { tagging: { tag_id: tag.id }, actor: "Casey Tester" }
    delete article_tagging_url(@article, tag), params: { actor: "Dana Tester" }

    steps = PaperTrailDiff.activity_timeline(@article, from: before, to: latest_version, associations: [ :tags ])
    credited = steps.reject(&:empty?).map do |step|
      tags = step.diff.associations.fetch("tags")
      [ step.source_boundary.whodunnit, tags.added.map(&:id), tags.removed.map(&:id) ]
    end

    assert_equal [ [ "Casey Tester", [ tag.id ], [] ], [ "Dana Tester", [], [ tag.id ] ] ], credited
  end

  private

  def latest_version
    @article.versions.reload.order(:created_at, :id).last
  end

  def tag_diff(from, to)
    PaperTrailDiff.compare(from, to, associations: [ :tags ]).associations.fetch("tags")
  end
end
