# Missing rows cannot be tested against a live relation's status filter. Keep
# their history separate and explicit, including rows with no destroy version.
class DeletedArticleHistory
  Entry = Data.define(:identity, :title, :steps)

  def initialize(identities, within:, group:)
    @identities = identities
    @within = within
    @group = group
  end

  # demo:code report.deleted
  def call
    @identities.map do |identity|
      type, id = identity
      version = Article.paper_trail.version_class
        .where(item_type: type, item_id: id, event: "destroy")
        .reorder(created_at: :desc, id: :desc).first
      root = version&.reify
      steps = if root
        PaperTrailDiff.activity_timeline(
          root, within: @within, group: @group, snapshots: true
        ).reject(&:empty?)
      end
      Entry.new(identity: identity, title: root&.title, steps: steps)
    end
  end
  # demo:code end
end
