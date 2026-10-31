require "test_helper"

# Parts of the gem's API the studio and report pages do not use, each checked
# against what DemoHistory recorded.
class GemFeaturesTest < ActiveSupport::TestCase
  setup do
    @article = DemoHistory.create!
    @versions = @article.versions.reorder(:created_at, :id).to_a
    # Written by Maya Chen's first revision, so it holds the article as a draft.
    @first_revision = @versions.find { |version| version.changeset["status"]&.last == "review" }
  end

  def identity(article) = [ "Article", article.id.to_s ]

  test "registers the gem's deprecator with Rails" do
    assert_same PaperTrailDiff.deprecator, Rails.application.deprecators[:paper_trail_diff]
  end

  test "compare_many answers as compare does, keyed by record" do
    other = Article.create!(title: "Other", status: "draft", body: "Body")
    pairs = [ { from: @first_revision, to: @article }, { from: :first, to: other } ]

    diffs = PaperTrailDiff.compare_many(pairs, associations: %w[comments])

    assert_equal [ identity(@article), identity(other) ], diffs.keys
    assert_equal PaperTrailDiff.compare(@first_revision, @article, associations: %w[comments]).to_h,
                 diffs.fetch(identity(@article)).to_h
    # `:first` is the earliest version, a create, so the record became present.
    assert_equal "Other", diffs.fetch(identity(other)).record_presence_change.to.attributes.fetch("title")
  end

  test "analyze_many answers as analyze does for each record" do
    other = Article.create!(title: "Other", status: "draft", body: "Body")

    results = PaperTrailDiff.analyze_many([ @article, other ], associations: %w[comments])

    assert_equal [ identity(@article), identity(other) ], results.keys
    assert_equal PaperTrailDiff.analyze(@article, associations: %w[comments]).diff.to_h,
                 results.fetch(identity(@article)).diff.to_h
  end

  test "analyze_scope over a fixed past window reports only the change inside it" do
    after_revision = @versions.fetch(@versions.index(@first_revision) + 1)
    window = @first_revision.created_at...after_revision.created_at

    report = PaperTrailDiff.analyze_scope(Article.all, within: window, limit: 10)
    diff = report.analyses.fetch(identity(@article)).diff

    assert_equal [ @article ], report.roots
    assert_equal({ from: "draft", to: "review" }, diff.attributes.fetch("status").to_h)
    assert_equal %w[metadata status title], diff.attributes.keys.sort
  end

  test "recorded_changes reads what each version stored" do
    steps = PaperTrailDiff.activity_timeline(@article, from: @first_revision, to: @versions.last,
                                             recorded_changes: true)
    source = steps.first.source_boundary

    assert_equal @first_revision.id, source.version_id
    assert_equal({ from: "draft", to: "review" }, source.recorded_changes.fetch("status").to_h)
    assert_equal PaperTrailDiff.recorded_changes(@first_revision).transform_values(&:to_h),
                 source.recorded_changes.transform_values(&:to_h)

    plain = PaperTrailDiff.activity_timeline(@article, from: @first_revision, to: @versions.last)
    assert_raises(PaperTrailDiff::ConfigurationError) { plain.first.source_boundary.recorded_changes }
  end

  test "change_rows flattens a report into rows attributed to their versions" do
    report = PaperTrailDiff.report(Article.all, since: @first_revision.created_at,
                                   associations: %w[comments], limit: 10)
    rows = report.change_rows.fetch(identity(@article)).map(&:to_h)

    status = rows.find { |row| row[:attribute] == "status" && row[:from] == "draft" }
    assert_equal({ change: :changed, to: "review", whodunnit: "Maya Chen", version_id: @first_revision.id },
                 status.slice(:change, :to, :whodunnit, :version_id))
    added = rows.find { |row| row[:attribute].nil? && row[:change] == :added && row[:association_path] == [ "comments" ] }
    assert added, "expected a row for a comment added after the first revision"
  end
end
