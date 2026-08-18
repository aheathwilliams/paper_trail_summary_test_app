# "What changed across every article recently?" -- the question `analyze_many`
# and a wall-clock window exist for, and the one the single-article studio on
# the root page cannot answer.
class ReportsController < ApplicationController
  WINDOWS = {
    "15m" => { label: "Last 15 minutes", seconds: 15 * 60 },
    "1h" => { label: "Last hour", seconds: 60 * 60 },
    "24h" => { label: "Last 24 hours", seconds: 24 * 60 * 60 },
    "7d" => { label: "Last 7 days", seconds: 7 * 24 * 60 * 60 }
  }.freeze
  DEFAULT_WINDOW = "24h"
  ASSOCIATIONS = %w[comments authorships tags document_revisions].freeze

  def show
    @window_key = WINDOWS.key?(params[:window]) ? params[:window] : DEFAULT_WINDOW
    @window_label = WINDOWS.fetch(@window_key).fetch(:label)
    @articles = Article.order(:title, :id).to_a
    @window = window_range
    return if @articles.empty?

    @results = build_report
    @incomplete_error = incomplete_window_error
  rescue PaperTrailDiff::Error => error
    @report_error = "#{error.class}: #{error.message}"
  end

  private

  def window_range
    # A window that ends now, which is what a report about recent activity
    # means. Ending at the present is exactly the case a version cannot close.
    Time.current - WINDOWS.fetch(@window_key).fetch(:seconds)..Time.current
  end

  # demo:code report.controller
  # One call covers every article. `analyze_many` selects each root's versions
  # and prepares their association history once for the whole batch, so the
  # query cost stays flat as the collection grows rather than repeating per
  # record.
  #
  # `close_on: :current` is what makes a window ending *now* answerable. A
  # PaperTrail version stores the state before its own event, so the final
  # change inside the window has no later version to reveal it; without this
  # the call raises IncompleteTimeRangeError rather than under-reporting.
  def build_report
    PaperTrailDiff.analyze_many(
      @articles,
      within: @window,
      associations: ASSOCIATIONS,
      close_on: :current
    )
  end
  # demo:code end

  # Runs the same window without `close_on:` purely to show what it protects
  # against. A real report would not do this; the demo does, because the error
  # is the single most common surprise when reporting on the present.
  def incomplete_window_error
    PaperTrailDiff.analyze_many(@articles, within: @window, associations: ASSOCIATIONS)
    nil
  rescue PaperTrailDiff::IncompleteTimeRangeError => error
    error.message
  end

  helper_method :changed_articles, :quiet_articles

  def changed_articles
    @articles.reject { |article| analysis_for(article).diff.empty? }
  end

  def quiet_articles
    @articles.select { |article| analysis_for(article).diff.empty? }
  end

  def analysis_for(article)
    @results.fetch(PaperTrailDiff::Endpoint.identity(article))
  end
  helper_method :analysis_for
end
