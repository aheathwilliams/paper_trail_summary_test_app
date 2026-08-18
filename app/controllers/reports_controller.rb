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
  ALL_STATUSES = "all"
  LIMIT = 500
  ASSOCIATIONS = %w[comments authorships tags document_revisions].freeze

  def show
    @window_key = WINDOWS.key?(params[:window]) ? params[:window] : DEFAULT_WINDOW
    @window_label = WINDOWS.fetch(@window_key).fetch(:label)
    @status = params[:status].presence || ALL_STATUSES
    @statuses = Article.distinct.order(:status).pluck(:status).compact
    @scope = article_scope
    @articles = @scope.order(:title, :id).to_a
    @window = window_range
    return if Article.none?

    @results, @unreachable = build_report
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

  def article_scope
    return Article.all if @status == ALL_STATUSES

    Article.where(status: @status)
  end

  # demo:code report.controller
  # `analyze_scope` takes the relation rather than a list this controller
  # assembled. It finds the roots whose history moved inside the window, loads
  # them, and analyzes them in a fixed number of queries -- the selection this
  # gem already performs, which a caller would otherwise reimplement.
  #
  # `close_on: :current` is what makes a window ending *now* answerable. A
  # PaperTrail version stores the state before its own event, so the final
  # change inside the window has no later version to reveal it; without this
  # the call raises IncompleteTimeRangeError rather than under-reporting.
  #
  # `unreachable` names roots that changed in the window but have no live row
  # left. A relation's conditions are evaluated against the live table, so a
  # destroyed root cannot be tested against them at all -- reporting them keeps
  # a deletions audit from quietly coming up short.
  def build_report
    PaperTrailDiff.analyze_scope(
      @scope,
      within: @window,
      associations: ASSOCIATIONS,
      limit: LIMIT,
      close_on: :current
    )
  end
  # demo:code end

  # Runs the same window without `close_on:` purely to show what it protects
  # against. A real report would not do this; the demo does, because the error
  # is the single most common surprise when reporting on the present.
  def incomplete_window_error
    PaperTrailDiff.analyze_scope(@scope, within: @window, associations: ASSOCIATIONS, limit: LIMIT)
    nil
  rescue PaperTrailDiff::IncompleteTimeRangeError => error
    error.message
  end

  helper_method :changed_articles, :quiet_articles, :reported_articles

  # Only roots the relation reached are in the result, so the page reads from
  # it rather than from the article list.
  def reported_articles
    @articles.select { |article| @results.key?(PaperTrailDiff::Endpoint.identity(article)) }
  end

  def changed_articles
    reported_articles.reject { |article| analysis_for(article).diff.empty? }
  end

  def quiet_articles
    reported_articles.select { |article| analysis_for(article).diff.empty? }
  end

  def analysis_for(article)
    @results.fetch(PaperTrailDiff::Endpoint.identity(article))
  end
  helper_method :analysis_for
end
