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

  # The final step removes the article, so it holds the article just before
  # deletion. The analysis's own endpoints can both be nil: an article created
  # inside the window did not exist when it began either.
  def last_state(analysis)
    analysis&.activity_timeline&.last&.diff&.record_presence_change&.from
  end
  # demo:code end
end
