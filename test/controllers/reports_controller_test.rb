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
    assert_select ".activity-card h3", text: @article.title
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

  test "an article with no versions in the window is listed as unchanged, not missing" do
    quiet = PaperTrail.request(enabled: false) do
      Article.create!(title: "Untouched", status: "draft", body: "No history at all.")
    end

    get report_url(window: "15m")

    assert_response :success
    assert_select ".activity-no-change", text: /#{Regexp.escape(quiet.title)}/
  end

  # An article created inside the window has no prior state, so its whole diff
  # is a record presence change. Rendering only attributes and associations left
  # those cards with a heading and nothing under it -- which every other
  # assertion here still passed.
  test "a card always shows what changed, including a lifecycle-only diff" do
    created_in_window = Article.create!(title: "Born inside", status: "draft", body: "New.")

    get report_url(window: "15m")

    assert_response :success
    card = css_select(".activity-card").find { |node| node.text.include?(created_in_window.title) }
    assert card, "expected a card for the article created inside the window"
    assert_match(/becomes present/, card.text)
  end

  test "shows the code that produced the report, read from the running files" do
    get report_url

    assert_response :success
    assert_select ".source-snippet figcaption code", text: "app/controllers/reports_controller.rb"
    assert_select ".source-snippet", html: /analyze_many/
  end
end
