require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "renders the interactive diff lab" do
    get root_url

    assert_response :success
    assert_select "h1", text: /PaperTrail/
    assert_select ".metric", count: 10
    assert_select ".result-view-tabs label", count: 4
    assert_select "#result-view-endpoint[checked]"
    assert_select "#to_id option[value='current'][selected]"
    assert_select ".result-panel", count: 4
    assert_select ".result-panel--checkpoints .timeline-step", count: 6
    assert_select "details.timeline-card:not(.activity-card)", count: 6
    assert_select "details.timeline-card:not(.activity-card)[open]", count: 6
    assert_select ".activity-timeline-section", count: 1
    assert_select ".activity-step.timeline-step"
    assert_select "details.activity-card.timeline-card[open]"
    assert_select "details.timeline-card:not([open])", count: 0
    assert_select ".activity-card > .activity-change-visual"
    assert_select ".activity-card > pre", count: 0
    assert_select ".activity-card .activity-overview"
    assert_select ".activity-card .activity-association-change"
    assert_select ".activity-boundary small", text: /by Maya Chen/
    assert_select ".activity-card details.activity-raw-result pre"
    assert_select ".result-panel--visible .visible-event-card"
    assert_select ".result-panel--visible .activity-no-change", count: 0
    assert_select ".visible-events-section code", text: /reject\(&:empty\?\)/
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

  test "regenerates the demo history" do
    post reset_demo_url

    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
    assert_equal "Apollo Notes — Final", Article.last.title
  end
end
