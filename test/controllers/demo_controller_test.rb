require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "renders the interactive diff lab" do
    # The lab defaults to the first update version through current state, so
    # every later root version contributes one checkpoint step. Deriving the
    # count keeps this test describing the view rather than the fixture's size.
    expected_steps = @article.versions.where(event: "update").count - 1

    get root_url

    assert_response :success
    assert_select "h1", text: /PaperTrail/
    # The net summary appears in both the overview and endpoint panels.
    assert_select ".metric", count: 20
    assert_select ".result-view-tabs label", count: 6
    assert_select "label[for='result-view-narratives']", text: /Narratives/
    assert_select "#result-view-overview[checked]"
    assert_select "#to_id option[value='current'][selected]"
    assert_select ".result-panel", count: 6
    assert_select ".result-panel--checkpoints .timeline-step", count: expected_steps
    assert_select "details.timeline-card:not(.activity-card)", count: expected_steps
    assert_select "details.timeline-card:not(.activity-card)[open]", count: expected_steps
    assert_select ".activity-timeline-section", count: 1
    assert_select ".activity-step.timeline-step"
    assert_select "details.activity-card.timeline-card[open]"
    # Cards start open everywhere except inside the overview's disclosure,
    # where the point is a scannable list rather than a wall of diffs.
    assert_select ".result-panel:not(.result-panel--overview) details.timeline-card:not([open])",
                  count: 0
    assert_select ".result-panel--overview details.timeline-card:not([open])"
    assert_select ".activity-card > .activity-change-visual"
    assert_select ".activity-card > pre", count: 0
    assert_select ".activity-card .activity-overview"
    assert_select ".activity-card .activity-association-change"
    assert_select ".activity-boundary small", text: /by Maya Chen/
    assert_select ".activity-card details.activity-raw-result pre"
    assert_select ".result-panel--overview .overview-activity summary strong",
                  text: /Show how it got there/
    assert_select ".result-panel--overview .overview-activity .activity-step"
    assert_select ".result-panel--visible .visible-event-card"
    assert_select ".result-panel--visible .activity-no-change", count: 0
    assert_select ".visible-events-section code", text: /reject\(&:empty\?\)/
    assert_select ".result-panel--narratives .narrative-event-step"
    assert_select ".narrative-sentence", text: /changed the status from draft to review/i
    assert_select ".narrative-sentence", text: /Luis Ortega replied to Jon Bell/
    assert_select ".narrative-detail--context", text: /The new opening works well/
    assert_select ".narrative-detail--added", text: /mission acronym is defined/
    assert_select "#ignore_attribute_bio"
    assert_select "#association_authors"
    assert_select "#association_comments"
    assert_select "#association_comments_replies"
    assert_select "#association_tags"
    assert_select "#association_authorships"
    assert_select "#association_versions", count: 0
    assert_select "#association_comments_article", count: 0
    assert_select "#ignore_path_comments_replies_body"
    assert_includes response.body, "Structured Ruby result"

    # Every result view explains how it was produced, from the real files.
    assert_select ".source-disclosure", count: 6
    assert_select ".source-snippet figcaption code", text: "app/models/article.rb"
    assert_select ".source-disclosure pre code", text: /has_paper_trail/
    assert_select ".source-disclosure pre code", text: /PaperTrailDiff\.analyze/
  end

  test "renders lifecycle snapshots and lifecycle-aware metrics" do
    create_version = @article.versions.find_by!(event: "create")

    get root_url, params: {
      article_id: @article.id,
      from_id: create_version.id,
      to_id: DemoController::CURRENT_ENDPOINT,
      associations_configured: "1",
      associations: %w[authors comments tags],
      blacklist_configured: "1",
      ignore: [ "updated_at" ]
    }

    assert_response :success
    assert_select ".endpoint-presence--created h3", text: "Article becomes present"
    assert_select ".endpoint-presence .activity-record--added"
    assert_select ".result-summary .metric:first-child strong", text: "4"
    assert_select ".result-summary .metric:first-child span", text: "attributes included"
    assert_select ".result-summary .metric:nth-child(2) strong", text: "2"
    assert_select ".result-summary .metric:nth-child(5) strong", text: "2"
    assert_select ".result-summary .metric:nth-child(8) strong", text: "2"
    assert_select ".result-panel--endpoint", text: /not duplicated as scalar changes/
    assert_select ".result-panel--endpoint", text: /No scalar attributes changed/, count: 0
    assert_select ".timeline-notice", text: /HABTM.*endpoint diff still uses.*current/i
  end

  test "compares a saved version with uncheckpointed current state" do
    latest_version = @article.versions.order(:created_at, :id).last
    @article.update_columns(title: "Live title beyond PaperTrail")

    get root_url, params: {
      article_id: @article.id,
      from_id: latest_version.id,
      to_id: DemoController::CURRENT_ENDPOINT,
      associations_configured: "1",
      blacklist_configured: "1",
      ignore: [ "updated_at" ]
    }

    assert_response :success
    assert_select "#to_id option[value='current'][selected]"
    assert_select ".change-card > code", text: "title"
    assert_select ".change-card .after", text: /Live title beyond PaperTrail/
    assert_select ".activity-timeline-section code", text: /to: article/
    assert_select ".activity-timeline-section", text: /Current Article ##{@article.id}/
    assert_select ".timeline-notice", count: 0
  end

  test "applies a configurable attribute blacklist" do
    versions = @article.versions.where(event: "update").order(:id)

    get root_url, params: {
      article_id: @article.id,
      from_id: versions.first.id,
      to_id: versions.last.id,
      ignore: "updated_at, title, status"
    }

    assert_response :success
    assert_select ".metric:first-child strong", text: "1"
    assert_select ".ignore-summary code", text: /title.*status/
  end

  test "uses the reflection-driven association picker as the allowlist" do
    versions = @article.versions.where(event: "update").order(:id)

    get root_url, params: {
      article_id: @article.id,
      from_id: versions.first.id,
      to_id: versions.last.id,
      associations_configured: "1",
      associations: [ "authors" ],
      blacklist_configured: "1",
      ignore: %w[updated_at bio]
    }

    assert_response :success
    assert_select "#ignore_attribute_bio[checked]"
    assert_select "#association_authors[checked]"
    assert_select "#association_comments[checked]", count: 0
    assert_select ".ignore-summary code", text: /associations: \["authors"\]/
    assert_select ".metric:nth-child(2) strong", text: "0"
    assert_select ".metric:nth-child(5) strong", text: "2"
  end

  test "submits exact nested paths and path-specific ignore rules" do
    versions = @article.versions.where(event: "update").order(:id)

    get root_url, params: {
      article_id: @article.id,
      from_id: versions.first.id,
      to_id: versions.last.id,
      associations_configured: "1",
      associations: [ "comments.replies" ],
      blacklist_configured: "1",
      ignore: [ "updated_at" ],
      ignore_paths: { "comments.replies" => [ "body" ] }
    }

    assert_response :success
    assert_select "#association_comments_replies[checked]"
    assert_select "#ignore_path_comments_replies_body[checked]"
    assert_select ".ignore-summary code", text: /comments\.replies.*body/
    assert_select ".payload pre", text: /"kind": "has_many"/
  end

  test "reports only one person's edits when a version scope is chosen" do
    versions = @article.versions.order(:id)
    params = {
      article_id: @article.id,
      from_id: versions.first.id,
      to_id: versions.last.id
    }

    get root_url, params: params
    assert_response :success
    everyone = css_select(".result-panel--checkpoints .timeline-step").length

    get root_url, params: params.merge(whodunnit: "Jon Bell")
    assert_response :success
    just_jon = css_select(".result-panel--checkpoints .timeline-step").length

    assert_select ".author-filter option[selected]", text: "Jon Bell"
    assert_select ".result-panel--checkpoints .filter-note", text: /Jon Bell/
    assert_operator just_jon, :<, everyone
    assert_operator just_jon, :>, 0
  end

  test "attributes a filtered transition to what that person actually changed" do
    # Maya Chen renames the article, and someone else edits it afterwards. The
    # transition reported for Maya must end at the version immediately after
    # her edit, not at the next edit of her own, or it would show her making
    # the other person's change too.
    scope = ->(relation) { relation.where(whodunnit: "Maya Chen") }
    steps = PaperTrailDiff.timeline(@article, from: :first, to: :last, version_scope: scope)

    assert_predicate steps, :any?
    steps.each do |step|
      assert_equal "Maya Chen", step.from_version.whodunnit
      following = @article.versions.where("id > ?", step.from_version.id).order(:id).first
      assert_equal following.id, step.to_version.id
    end
  end

  test "regenerates the demo history" do
    post reset_demo_url

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
    assert_equal "Apollo Notes — Final", Article.last.title
  end
end
