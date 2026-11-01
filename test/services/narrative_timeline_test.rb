require "test_helper"

class NarrativeTimelineTest < ActiveSupport::TestCase
  setup do
    @article = DemoHistory.create!
    @from = @article.versions.where(event: "update").order(:created_at, :id).first
    @to = @article.versions.order(:created_at, :id).last
    @steps = PaperTrailDiff.activity_timeline(
      @article,
      from: @from,
      to: @to,
      associations: %w[
        authors authors.authorships authorships authorships.author
        comments comments.replies tags
      ],
      ignore: [ "updated_at" ],
      snapshots: true
    )
  end

  test "humanizes scalar changes and reply conversations" do
    items = events.flat_map(&:items)

    status = items.find { |item| item.sentence.to_s.include?("changed the status") }
    reply = items.find { |item| item.sentence.to_s == "Luis Ortega replied to Jon Bell." }

    assert_equal "Maya Chen changed the status from draft to review.", status.sentence.to_s
    assert_equal %w[draft review], status.sentence.segments.select(&:code).map(&:text)
    assert_equal [ "Jon Bell's comment", "Luis Ortega's reply" ], reply.details.map { _1.label.to_s }
    assert_equal "The new opening works well.", reply.details.first.body
    assert_equal "The mission acronym is defined in the second paragraph.", reply.details.last.body
  end

  test "deduplicates a record reached through multiple association paths" do
    items = events.flat_map(&:items)
    profile_edits = items.select { |item| item.sentence.to_s.include?("author profile") }
    luis_additions = items.select do |item|
      item.sentence.to_s.start_with?("Luis Ortega added themselves as an author")
    end

    assert_equal 1, profile_edits.length
    assert_equal 1, luis_additions.length
    assert items.none? { |item| item.sentence.to_s.include?("credited Luis Ortega") }
  end

  test "carries the join's role onto the sentence about the author" do
    texts = events.flat_map(&:items).map { _1.sentence.to_s }

    assert_includes texts,
                    "Luis Ortega added themselves as an author to the article, credited as contributor."
    assert_includes texts, "Luis Ortega changed their own byline credit from Luis Ortega to L. Ortega."
    assert texts.none? { |text| text.include?("an author's") }
  end

  test "never names the same person twice in one sentence" do
    steps = PaperTrailDiff.activity_timeline(
      @article, from: @article.versions.order(:created_at, :id).first, to: @to,
      associations: %w[authors authorships authorships.author comments comments.replies],
      ignore: [ "updated_at" ], snapshots: true
    )
    items = NarrativeTimeline.new(steps.reject(&:empty?)).call.flat_map(&:items)
    texts = items.map { _1.sentence.to_s }

    assert_includes texts, "Jon Bell replied to their own comment."
    assert_includes texts, "Jon Bell removed their reply to their own comment."
    assert_includes texts, "Maya Chen removed themselves as an author from the article."
    # Values are left out: a byline can rightly be its author's own name.
    repeated = items.map { |item| item.sentence.segments.reject(&:code).map(&:text).join }
      .select { |prose| Author.pluck(:name).any? { |name| prose.scan(name).length > 1 } }
    assert_empty repeated
  end

  test "names other records by their label" do
    article = Article.create!(title: "Plans", status: "draft", body: "Body")
    from = article.versions.last
    PaperTrail.request(whodunnit: "Ann") { article.document_revisions.create!(label: "Budget plan") }
    Article.transaction { Article.find(article.id).paper_trail.save_with_version }
    steps = PaperTrailDiff.activity_timeline(
      article, from: from, to: article.versions.last, associations: [ "document_revisions" ],
      snapshots: true
    )
    texts = NarrativeTimeline.new(steps.reject(&:empty?)).call.flat_map(&:items).map { _1.sentence.to_s }

    assert_includes texts, "Ann added the Budget plan document revision."
  end

  test "keeps a value with backticks in it as one value" do
    article = Article.create!(title: "Run `rake` first", status: "draft", body: "Body")
    steps = PaperTrailDiff.activity_timeline(article, snapshots: true)
    created = NarrativeTimeline.new(steps.reject(&:empty?)).call.flat_map(&:items)
      .find { |item| item.kind == :article_created }

    assert_equal [ "Run `rake` first" ], created.sentence.segments.select(&:code).map(&:text)
  end

  # Tag membership is recorded only at article versions. The seed saves each
  # tag change between two checkpoints by the person who made it, and always
  # from a freshly loaded article, so the narrative credits that person and
  # reports no tag the seed did not touch.
  test "narrates the seed's tag changes and credits whoever made them" do
    steps = PaperTrailDiff.activity_timeline(
      @article, from: @from, to: @to, associations: %w[tags], snapshots: true
    )
    items = NarrativeTimeline.new(steps.reject(&:empty?)).call.flat_map(&:items)
    texts = items.select { _1.kind.to_s.start_with?("tag_") }.map { _1.sentence.to_s }

    assert_equal [
      "Maya Chen changed description on the Apollo tag.",
      "Maya Chen removed the Needs sources tag from the article.",
      "Priya Shah added the Verified tag to the article."
    ], texts
  end

  test "produces no event without a humanized item" do
    assert_equal @steps.reject(&:empty?).length, events.length
    assert events.all? { |event| event.items.any? }
  end

  private

  def events
    @events ||= NarrativeTimeline.new(@steps.reject(&:empty?)).call
  end
end
