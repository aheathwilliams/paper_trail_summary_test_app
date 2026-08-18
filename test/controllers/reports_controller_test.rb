require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  test "reports what changed across every article in a wall-clock window" do
    get report_url

    assert_response :success
    assert_select "h1", text: /activity report/i
    # The seeded history is minutes old, so the default 24h window covers it.
    assert_select ".report-card h3", text: @article.title
  end

  test "honours the selected window and rejects an unknown one" do
    get report_url(window: "15m")
    assert_response :success
    assert_select "h2", text: "Last 15 minutes"

    # An unrecognised window falls back rather than raising, since the value
    # arrives from a query string.
    get report_url(window: "; DROP TABLE")
    assert_response :success
    assert_select "h2", text: "Last 24 hours"
  end

  # The whole reason the report passes `close_on: :current`. A window ending at
  # the present has no version after its final change, so without it the call
  # raises rather than under-reporting -- and the page shows that on purpose.
  test "shows what close_on: :current protects against" do
    get report_url

    assert_response :success
    assert_select "pre code", text: /IncompleteTimeRangeError|later root version/
  end

  # Where `analyze_many` returns an empty Analysis for every record handed to
  # it, `analyze_scope` selects only the roots whose history moved inside the
  # window -- so one with no versions there is absent rather than empty, and the
  # page says how many of the collection the relation actually reached.
  test "an article with no history in the window is not selected at all" do
    quiet = PaperTrail.request(enabled: false) do
      Article.create!(title: "Untouched", status: "draft", body: "No history at all.")
    end

    get report_url(window: "15m")

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

    get report_url(status: "draft")

    assert_response :success
    assert_select ".report-card h3", text: article.title, count: 0

    get report_url(status: "approved")

    assert_response :success
    assert_select ".report-card h3", text: article.title
  end

  # An article created inside the window has no prior state, so its whole diff
  # is a record presence change. Rendering only attributes and associations left
  # those cards with a heading and nothing under it -- which every other
  # assertion here still passed.
  test "a card always shows what changed, including a lifecycle-only diff" do
    created_in_window = Article.create!(title: "Born inside", status: "draft", body: "New.")

    get report_url(window: "15m")

    assert_response :success
    card = css_select(".report-card").find { |node| node.text.include?(created_in_window.title) }
    assert card, "expected a card for the article created inside the window"
    assert_match(/becomes present/, card.text)
  end

  test "shows the code that produced the report, read from the running files" do
    get report_url

    assert_response :success
    assert_select ".source-snippet figcaption code", text: "app/controllers/reports_controller.rb"
    assert_select ".source-snippet", html: /analyze_scope/
  end
end
