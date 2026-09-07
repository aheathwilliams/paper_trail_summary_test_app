# "What changed across every article recently?" -- the question `report`
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
  # Live activity cannot reconstruct HABTM membership. The studio still offers
  # tag endpoint diffs; this report explicitly requests the supported graph.
  ASSOCIATIONS = %w[comments.replies authorships.author document_revisions].freeze
  DELETED_LIMIT = 25

  def show
    @window_key = WINDOWS.key?(params[:window]) ? params[:window] : DEFAULT_WINDOW
    @window_label = WINDOWS.fetch(@window_key).fetch(:label)
    @status = Article::STATUSES.include?(params[:status]) ? params[:status] : ALL_STATUSES
    @status_basis = params[:status_basis] == "historical" ? "historical" : "current"
    # Historical values may have disappeared from the live table entirely.
    @statuses = Article::STATUSES
    @scope = article_scope.order(:title, :id)
    @window = window_range
    @group = params[:group] == "events" ? nil : :transaction

    report = build_report
    @results = report.analyses
    @unreachable = report.unreachable
    @articles = report.roots
    @deleted_histories = DeletedArticleHistory.new(
      report.deleted.first(DELETED_LIMIT).to_h
    ).call
    @incomplete_error = incomplete_window_error if params[:explain_closure] == "1"
  rescue PaperTrailDiff::Error => error
    @report_error = "#{error.class}: #{error.message}"
  end

  private

  def window_range
    # A window that ends now, which is what a report about recent activity
    # means. Ending at the present is exactly the case a version cannot close.
    now = Time.current
    now - WINDOWS.fetch(@window_key).fetch(:seconds)..now
  end

  def article_scope
    return Article.all if @status == ALL_STATUSES || historical_status?

    Article.where(status: @status)
  end

  def historical_status?
    @status_basis == "historical"
  end
  helper_method :historical_status?

  # demo:code report.filter
  def historical_filter
    return unless historical_status? && @status != ALL_STATUSES

    { status: @status }
  end
  # demo:code end

  # demo:code report.controller
  # `report` returns recent activity through now; it handles the live ending.
  # Deleted histories are loaded as a separate batch because current SQL filters
  # cannot establish whether a deleted row matched the live population.
  def build_report
    PaperTrailDiff.report(
      @scope,
      since: @window.begin,
      associations: ASSOCIATIONS,
      limit: LIMIT,
      include_deleted: true,
      group: @group,
      snapshots: true,
      historical_filter: historical_filter
    )
  end
  # demo:code end

  # Runs the same window without `close_on:` purely to show what it protects
  # against, only when explicitly requested. Historical selection reads candidate
  # states, so repeating it on every report request can double that work.
  def incomplete_window_error
    PaperTrailDiff.analyze_scope(
      @scope, within: @window, associations: ASSOCIATIONS, limit: LIMIT,
      historical_filter: historical_filter
    )
    nil
  rescue PaperTrailDiff::IncompleteTimeRangeError => error
    error.message
  end

  def closure_example_params
    { window: @window_key, status: @status, status_basis: @status_basis,
      group: @group ? "transaction" : "events", explain_closure: "1" }
  end
  helper_method :closure_example_params

  helper_method :changed_articles, :quiet_articles, :reported_articles

  # Only roots the relation reached are in the result, so the page reads from
  # it rather than from the article list.
  def reported_articles
    @articles
  end

  def changed_articles
    reported_articles.reject { |article| quiet_analysis?(analysis_for(article)) }
  end

  def quiet_articles
    reported_articles.select { |article| quiet_analysis?(analysis_for(article)) }
  end

  def analysis_for(article)
    @results.fetch([ article.class.base_class.name, article.id.to_s ])
  end
  helper_method :analysis_for

  def quiet_analysis?(analysis)
    analysis.diff.empty? && analysis.activity_timeline.all?(&:empty?)
  end
end
