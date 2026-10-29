# Presentation data from the gem's batch result; this class performs no queries.
class DeletedArticleHistory
  Entry = Data.define(:identity, :title, :steps)

  def initialize(analyses)
    @analyses = analyses
  end

  # demo:code report.deleted
  def call
    @analyses.map do |identity, analysis|
      Entry.new(
        identity: identity,
        title: last_state(analysis)&.attributes&.fetch("title", nil),
        steps: analysis&.activity_timeline&.reject(&:empty?)
      )
    end
  end

  private

  # The window closes on the deletion, so the article's last state is the one
  # the final step started from. An article created inside the window has no
  # state at its start either, so the analysis's own endpoints can both be nil.
  def last_state(analysis)
    return unless analysis

    analysis.activity_timeline.reverse_each.find(&:from_snapshot)&.from_snapshot ||
      analysis.from_snapshot
  end
  # demo:code end
end
