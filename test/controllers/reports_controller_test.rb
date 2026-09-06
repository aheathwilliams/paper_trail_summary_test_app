require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "reports what changed across every article in a wall-clock window" do
    get_report

    assert_response :success
    assert_select "h1", text: /activity report/i
    # The seeded history is minutes old, so the default 24h window covers it.
    assert_select ".report-card h3", text: @article.title
  end

  test "honours the selected window and rejects an unknown one" do
    get_report(window: "15m")
    assert_response :success
    assert_select "h2", text: "Last 15 minutes"

    # An unrecognised window falls back rather than raising, since the value
    # arrives from a query string.
    get_report(window: "; DROP TABLE")
    assert_response :success
    assert_select "h2", text: "Last 24 hours"
  end

  # The whole reason the report passes `close_on: :current`. A window ending at
  # the present has no version after its final change, so without it the call
  # raises rather than under-reporting -- and the page shows that on purpose.
  test "shows what close_on: :current protects against when explicitly requested" do
    get_report(explain_closure: "1")

    assert_response :success
    assert_select "pre code", { text: /IncompleteTimeRangeError|later root version/ }, response.body
  end

  # Where `analyze_many` returns an empty Analysis for every record handed to
  # it, `analyze_scope` selects only the roots whose history moved inside the
  # window -- so one with no versions there is absent rather than empty, and the
  # page says how many of the collection the relation actually reached.
  test "an article with no history in the window is not selected at all" do
    quiet = PaperTrail.request(enabled: false) do
      Article.create!(title: "Untouched", status: "draft", body: "No history at all.")
    end

    get_report(window: "15m")

    assert_response :success
    assert_select ".report-card h3", text: quiet.title, count: 0
    assert_select "p.lede", text: /reached by the relation/
  end

  # The caveat the page states in prose, exercised: the seeded article was a
  # draft while the window was open and is approved now, so filtering on its
  # historical status finds nothing.
  test "the relation selects on current state, not on state during the window" do
    article = @article
    assert_equal "approved", article.status

    get_report(status: "draft")

    assert_response :success
    assert_select ".report-card h3", text: article.title, count: 0

    get_report(status: "approved")

    assert_response :success
    assert_select ".report-card h3", text: article.title
  end

  # An article created inside the window has no prior state, so its whole diff
  # is a record presence change. Rendering only attributes and associations left
  # those cards with a heading and nothing under it -- which every other
  # assertion here still passed.
  test "a card always shows what changed, including a lifecycle-only diff" do
    created_in_window = Article.create!(title: "Born inside", status: "draft", body: "New.")

    get_report(window: "15m")

    assert_response :success
    card = css_select(".report-card").find { |node| node.text.include?(created_in_window.title) }
    assert card, "expected a card for the article created inside the window"
    assert_match(/becomes present/, card.text)
  end

  test "shows the code that produced the report, read from the running files" do
    get_report

    assert_response :success
    assert_select ".source-snippet figcaption code", { text: "app/controllers/reports_controller.rb" }, response.body
    assert_select ".source-snippet", html: /analyze_scope/
  end
  test "retains narrative context and serializes source metadata for grouped activity" do
    get_report(group: "transaction")
    assert_response :success
    grouped = css_select(".report-event").length
    assert_select ".report-event .narrative-sentence", text: /Maya Chen/
    assert_select ".report-event .activity-raw-result pre", text: /"whodunnit"/
    assert_select ".report-event .activity-raw-result pre", text: /"transaction_id"/

    get_report(group: "events")
    assert_response :success
    assert_operator css_select(".report-event").length, :>, grouped
  end

  test "shows activity even when edits return to the starting state" do
    travel_to 2.days.ago do
      VersionClock.reset!
      @reverted = Article.create!(title: "Reverted", status: "draft", body: "Original")
    end
    VersionClock.reset!
    PaperTrail.request(whodunnit: "Reviser") { @reverted.update!(body: "Temporary") }
    PaperTrail.request(whodunnit: "Restorer") { @reverted.update!(body: "Original") }

    get_report(window: "15m", group: "events")

    assert_response :success
    card = css_select(".report-card").find { |node| node.at_css("h3").text == "Reverted" }
    assert card, "expected reverted edits to remain visible"
    assert_match(/returned to its starting state/, card.text)
    assert_match(/Temporary/, card.text)
    assert_match(/Restorer/, card.text)
  end

  test "shows deleted history even when no live articles remain" do
    title = @article.title
    Article.destroy_all

    get_report

    assert_response :success
    assert_select ".deleted-history h3", text: /#{Regexp.escape(title)}/
    assert_select ".deleted-history", text: /Deleted Article/
    assert_select ".deleted-history .narrative-sentence", text: /removed|deleted/i
  end

  test "keeps deleted history separate from the current status filter" do
    @article.destroy!

    get_report(status: "draft")

    assert_response :success
    assert_select ".deleted-history h3", text: /Apollo Notes/
    assert_select "p", text: /regardless of the current status filter/
  end

  test "states when a missing root has no destroy version" do
    Article.create!(title: "Missing destroy", status: "draft", body: "Gone").delete

    get_report

    assert_response :success
    assert_select ".deleted-history", text: /No destroy version is available/
  end
  test "bounds deleted reconstruction and explains when more history remains" do
    26.times do |index|
      Article.create!(title: "Missing #{index}", status: "draft", body: "Gone").delete
    end

    get_report

    assert_response :success
    assert_select ".deleted-history", count: 25
    assert_select "p", text: /Showing the first 25 of\s+26 missing articles/
  end

  test "historical status finds a moved article that current status excludes" do
    get_report(status: "review", status_basis: "current")
    assert_select ".report-card h3", text: @article.title, count: 0

    get_report(status: "review", status_basis: "historical")
    assert_response :success
    assert_select ".report-card h3", text: @article.title
    assert_select "select[name='status'] option[value='review'][selected]"
    assert_select ".selection-explainer", text: /whole selected window/
    assert_select ".source-snippet", html: /historical_filter/
  end

  test "historical status includes only matching deleted histories" do
    matching = Article.create!(title: "Deleted review", status: "review", body: "Gone")
    rejected = Article.create!(title: "Deleted draft", status: "draft", body: "Gone")
    matching.destroy!
    rejected.destroy!

    get_report(status: "review", status_basis: "historical")
    assert_response :success
    assert_select ".deleted-history h3", text: /Deleted review/
    assert_select ".deleted-history h3", text: /Deleted draft/, count: 0
    assert_select "p", text: /Nonmatching histories are excluded/
  end

  test "historical selection does not silently include the final live state" do
    final = Article.create!(title: "Final review", status: "draft", body: "Body")
    final.update!(status: "review")
    born = Article.create!(title: "Born in review", status: "review", body: "Body")

    get_report(status: "review", status_basis: "current")
    assert_select ".report-card h3", text: final.title
    assert_select ".report-card h3", text: born.title

    get_report(status: "review", status_basis: "historical")
    assert_select ".report-card h3", text: final.title, count: 0
    assert_select ".report-card h3", text: born.title, count: 0
    assert_select ".selection-explainer", text: /does not make the current state eligible/
  end

  test "only historical states recorded inside the chosen window are eligible" do
    travel_to 2.hours.ago do
      VersionClock.reset!
      @older = Article.create!(title: "Earlier review", status: "review", body: "Body")
      @older.update!(status: "approved")
    end
    VersionClock.reset!
    @older.update!(body: "Current edit while approved")

    get_report(window: "15m", status: "review", status_basis: "historical")
    assert_select ".report-card h3", text: @older.title, count: 0

    get_report(window: "24h", status: "review", status_basis: "historical")
    assert_select ".report-card h3", text: @older.title
  end

  test "unknown selection values fall back to current state and any status" do
    get_report(status: "unknown", status_basis: "unknown")
    assert_response :success
    assert_select "select[name='status_basis'] option[value='current'][selected]"
    assert_select "select[name='status'] option[value='all'][selected]"
  end

  test "any historical status preserves candidates without a predicate" do
    Article.create!(title: "No destroy boundary", status: "review", body: "Gone").delete
    get_report(status_basis: "historical")
    assert_response :success
    assert_select ".selection-explainer", text: /no historical predicate/
    assert_select ".deleted-history", text: /No destroy version is available/
  end

  test "example dataset preserves existing articles and demonstrates both selections" do
    assert_difference -> { Article.count }, 2 do
      post report_examples_url
    end
    assert_redirected_to report_url(status_basis: "historical", status: "review", group: "events")
    assert_equal @article.title, @article.reload.title

    get_report(status_basis: "historical", status: "review", group: "events")
    assert_select ".report-card h3", text: "History example: moved out of Review"
    assert_select ".deleted-history h3", text: /History example: deleted in Review/
    assert_select ".report-card h3", text: "History example: final event entered Review", count: 0

    get_report(status_basis: "current", status: "review")
    assert_select ".report-card h3", text: "History example: final event entered Review"
    assert_select ".report-card h3", text: "History example: moved out of Review", count: 0
  end

  test "normal historical reports select candidates once" do
    selections = []
    subscriber = ->(*args) do
      sql = args.last.fetch(:sql)
      selections << sql if sql.start_with?('SELECT DISTINCT "versions"."item_id" FROM "versions"')
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get_report(status: "review", status_basis: "historical")
    end

    assert_response :success
    assert_equal 1, selections.length
    assert_select "a[href*='explain_closure=1'][href*='status_basis=historical']"
    assert_select "a[href*='explain_closure=1'][href*='status=review']"
  end

  private

  def get_report(**query)
    # VersionClock may advance tightly spaced versions beyond the current tick.
    # These tests report after their writes; make that boundary deterministic.
    latest = Article.paper_trail.version_class.maximum(:created_at)
    report_time = [ Time.current, latest ].compact.max + 1.second
    travel_to(report_time) { get report_url(**query) }
  end
end
