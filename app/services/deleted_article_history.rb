# Presentation data from the gem's batch result; this class performs no queries.
class DeletedArticleHistory
  Entry = Data.define(:identity, :title, :steps)

  def initialize(analyses)
    @analyses = analyses
  end

  # demo:code report.deleted
  def call
    @analyses.map do |identity, analysis|
      snapshot = analysis&.to_snapshot || analysis&.from_snapshot
      Entry.new(
        identity: identity,
        title: snapshot&.attributes&.fetch("title", nil),
        steps: analysis&.activity_timeline&.reject(&:empty?)
      )
    end
  end
  # demo:code end
end
