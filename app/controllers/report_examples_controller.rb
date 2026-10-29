class ReportExamplesController < ApplicationController
  def create
    HistoricalReportExamples.create!
    redirect_to report_path(status_basis: "historical", status: "review", group: "events"),
      notice: "Added historical status examples. Review matches moved and deleted articles; the final-event example appears under Current state."
  end
end
