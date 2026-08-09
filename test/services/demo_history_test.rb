require "test_helper"

class DemoHistoryTest < ActiveSupport::TestCase
  test "builds scalar and association changes for the diff APIs" do
    article = DemoHistory.create!
    versions = article.versions.where(event: "update").order(:id).to_a

    endpoint_diff = PaperTrailDiff.compare(
      versions.first,
      versions.last,
      associations: [ "comments.replies", :authors, :tags ]
    )
    comments = endpoint_diff.associations.fetch("comments")
    authors = endpoint_diff.associations.fetch("authors")
    tags = endpoint_diff.associations.fetch("tags")
    replies = comments.changed.first.associations.fetch("replies")

    assert_equal 7, versions.length
    assert_equal %w[body status title], endpoint_diff.attributes.keys
    assert_equal 1, comments.added.length
    assert_equal 1, comments.changed.length
    assert_equal 2, authors.added.length
    assert_equal 1, authors.removed.length
    assert_equal :has_and_belongs_to_many, tags.kind
    assert_equal 1, tags.added.length
    assert_equal 1, tags.removed.length
    assert_equal 1, tags.changed.length
    assert_equal 1, replies.added.length
    assert_equal 1, replies.removed.length
    assert_equal 1, replies.changed.length

    author_edit_diff = PaperTrailDiff.compare(
      versions.second,
      versions.third,
      associations: [ :authors ]
    ).associations.fetch("authors")

    assert_equal 1, author_edit_diff.added.length
    assert_equal 1, author_edit_diff.changed.length

    ignored_author_edit = PaperTrailDiff.compare(
      versions.second,
      versions.third,
      associations: [ :authors ],
      ignore: [ :bio, :updated_at ]
    ).associations.fetch("authors")

    assert_equal 1, ignored_author_edit.added.length
    assert_empty ignored_author_edit.changed

    path_ignored = PaperTrailDiff.compare(
      versions.first,
      versions.last,
      associations: [ "comments.replies" ],
      ignore: {
        all: [ :updated_at ],
        paths: { "comments.replies" => [ :body ] }
      }
    )
    path_comments = path_ignored.associations.fetch("comments")
    path_replies = path_comments.changed.first.associations.fetch("replies")

    assert path_ignored.attributes.key?("body")
    assert path_comments.changed.first.attributes.key?("body")
    assert_empty path_replies.changed
    assert_equal 1, path_replies.added.length
    assert_equal 1, path_replies.removed.length

    membership_diff = PaperTrailDiff.compare(
      versions.third,
      versions.fourth,
      associations: [ :comments ]
    ).associations.fetch("comments")

    assert_equal 1, membership_diff.added.length
    assert_equal 1, membership_diff.removed.length

    steps = PaperTrailDiff.timeline(
      article,
      from: versions.first,
      to: versions.last,
      associations: [ :comments ]
    )
    assert_equal 6, steps.length

    join_diff = PaperTrailDiff.compare(
      versions.third,
      versions.last,
      associations: [ "authorships.author" ]
    ).associations.fetch("authorships")
    credited = join_diff.changed.find do |change|
      change.attributes.key?("credited_as")
    end

    assert_equal "L. Ortega", credited.attributes.fetch("credited_as").to
    assert_equal "co-lead", credited.attributes.fetch("role").to
  end
end
