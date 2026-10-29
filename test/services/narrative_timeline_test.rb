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
      item.sentence.to_s.include?("added Luis Ortega as an author")
    end

    assert_equal 1, profile_edits.length
    assert_equal 1, luis_additions.length
    assert items.none? { |item| item.sentence.to_s.include?("credited Luis Ortega") }
  end

  test "keeps a value with backticks in it as one value" do
    article = Article.create!(title: "Run `rake` first", status: "draft", body: "Body")
    steps = PaperTrailDiff.activity_timeline(article, snapshots: true)
    created = NarrativeTimeline.new(steps.reject(&:empty?)).call.flat_map(&:items)
      .find { |item| item.kind == :article_created }

    assert_equal [ "Run `rake` first" ], created.sentence.segments.select(&:code).map(&:text)
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
