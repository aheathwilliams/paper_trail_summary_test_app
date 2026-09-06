# A small dataset added explicitly by the user, separate from the studio seed.
# Each invocation is one transaction; destroy versions survive for the report.
class HistoricalReportExamples
  def self.create!
    PaperTrail.request(whodunnit: "Historical report example") do
      Article.transaction do
        moved = Article.create!(title: "History example: moved out of Review", status: "review", body: "Approved now, previously in review.")
        moved.update!(status: "approved")

        deleted = Article.create!(title: "History example: deleted in Review", status: "review", body: "Its destroy version records the review state.")
        deleted.destroy!

        final = Article.create!(title: "History example: final event entered Review", status: "draft", body: "The live state is review; the recorded prior state is draft.")
        final.update!(status: "review")
      end
    end
  end
end
