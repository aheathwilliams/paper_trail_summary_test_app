# Checks the gem's rebuilt history against the states this application really
# went through. A generated history applies random edits, one transaction at
# a time, and records the article's graph after each with plain Active Record.
# Every reconstruction is then compared with the state it claims to show. The
# gem has an oracle suite of its own; this one runs on the application's real
# models and configuration.
module HistoryOracle
  PATHS = %w[comments.replies authorships.author authors.authorships tags document_revisions].freeze
  # A HABTM cannot be replayed through the current record.
  ACTIVITY_PATHS = (PATHS - %w[tags]).freeze
  ACTORS = [ "Maya Chen", "Jon Bell", "Priya Shah", "Luis Ortega" ].freeze

  module_function

  def canon(value)
    case value
    when Hash then value.to_h { |key, item| [ key.to_s, canon(item) ] }.sort.to_h
    when Array then value.map { |item| canon(item) }
    when Time, ActiveSupport::TimeWithZone, DateTime then value.utc.iso8601(6)
    else value
    end
  end

  # As the reference says: the key of an included belongs_to, and the key a
  # has_many child points back to its parent with, are left out.
  def node(record, associations = {}, drop: [])
    attributes = canon(record.attributes.except("id", "updated_at", *drop))
    { "type" => record.class.base_class.name, "id" => record.id,
      "attributes" => attributes, "associations" => associations }
  end

  # The article's graph for PATHS, read with plain Active Record.
  def live(article_id)
    article = Article.find(article_id)
    comments = Comment.where(article_id: article.id).order(:id).map do |comment|
      replies = Reply.where(comment_id: comment.id).order(:id).map { |reply| node(reply, drop: %w[comment_id]) }
      node(comment, { "replies" => replies }, drop: %w[article_id])
    end
    authorships = Authorship.where(article_id: article.id).order(:id).map do |join|
      node(join, { "author" => [ node(Author.find(join.author_id)) ] }, drop: %w[article_id author_id])
    end
    authors = Author.where(id: Authorship.where(article_id: article.id).select(:author_id)).order(:id).map do |author|
      joins = Authorship.where(author_id: author.id).order(:id).map { |join| node(join, drop: %w[author_id]) }
      node(author, { "authorships" => joins })
    end
    tags = Tag.where(id: article.tags.select(:id)).order(:id).map { |tag| node(tag) }
    revisions = DocumentRevision.where(attachable: article).order(:id)
      .map { |revision| node(revision, drop: %w[attachable_id attachable_type]) }
    node(article, { "authors" => authors, "authorships" => authorships, "comments" => comments,
                    "document_revisions" => revisions, "tags" => tags })
  end

  # A gem snapshot in the same shape.
  def snapshot(value)
    return nil unless value

    walk = lambda do |hash|
      associations = (hash[:associations] || {}).to_h do |name, association|
        [ name.to_s, association[:records].map { |record| walk.call(record) } ]
      end
      { "type" => hash[:type], "id" => hash[:id], "attributes" => canon(hash[:attributes]),
        "associations" => associations }
    end
    walk.call(value.to_h)
  end

  def restrict(state, names)
    state&.merge("associations" => state["associations"].slice(*names))
  end

  # The first place two states differ, as a short path.
  def difference(expected, actual, path = "$")
    return if expected == actual
    unless (expected.is_a?(Hash) && actual.is_a?(Hash)) || (expected.is_a?(Array) && actual.is_a?(Array))
      return "#{path}: expected #{expected.inspect.first(120)}, got #{actual.inspect.first(120)}"
    end

    if expected.is_a?(Array)
      ids = ->(records) { records.map { |record| record.is_a?(Hash) ? [ record["type"], record["id"] ] : record } }
      return "#{path}: expected #{ids.call(expected)}, got #{ids.call(actual)}" if expected.length != actual.length

      expected.zip(actual).each_with_index do |(left, right), index|
        found = difference(left, right, "#{path}[#{index}]")
        return found if found
      end
      return
    end

    (expected.keys | actual.keys).each do |key|
      found = difference(expected[key], actual[key], "#{path}.#{key}")
      return found if found
    end
    nil
  end

  # The live state after each transaction, by the versions it wrote.
  class Recorder
    Entry = Struct.new(:name, :version_ids, :state, :after, :habtm_first, keyword_init: true)
    attr_reader :entries

    def initialize(&article_id)
      @article_id = article_id
      @entries = [ Entry.new(name: :none, version_ids: []) ]
    end

    # `habtm_first:` marks a transaction that changes tags before it writes
    # the article's version: PT-AT records that version's tags after the
    # change, so its state is the transaction's end rather than its start.
    def run(name, actor, habtm_first: false, &block)
      before = PaperTrail::Version.maximum(:id) || 0
      PaperTrail.request(whodunnit: actor) { ActiveRecord::Base.transaction(&block) }
      ids = PaperTrail::Version.where("id > ?", before).order(:id).pluck(:id)
      id = @article_id.call
      @entries << Entry.new(name: name, version_ids: ids, state: id && HistoryOracle.live(id),
                            after: Time.now.utc, habtm_first: habtm_first)
    end

    # The state a version of the article stands for: the one before the
    # transaction that wrote it.
    def expected(version)
      index = @entries.index { |entry| entry.version_ids.include?(version.id) }
      raise "no recorded transaction wrote version #{version.id}" unless index&.positive?

      entry = @entries.fetch(index)
      return entry.state if entry.habtm_first && version.item_type == "Article"

      @entries.fetch(index - 1).state
    end

    def first_of_transaction?(version_id)
      @entries.find { |entry| entry.version_ids.include?(version_id) }&.version_ids&.min == version_id
    end

    def final = @entries.last
  end

  # Random edits through the application's models, one transaction each.
  class History
    OPERATIONS = %i[
      edit_article edit_article edit_metadata add_comment edit_comment destroy_comment
      add_reply edit_reply destroy_reply add_author attach_shared_author edit_author
      edit_authorship destroy_authorship attach_tag attach_new_tag detach_tag edit_tag
      create_and_attach_tag_with_checkpoint add_revision relabel_revision destroy_revision
      attach_file checkpoint touch_article save_in_one_pass edit_other_article
    ].freeze
    # These record their own transactions.
    SELF_RECORDED = %i[attach_tag attach_new_tag detach_tag create_and_attach_tag_with_checkpoint].freeze

    attr_reader :article, :recorder

    def initialize(seed, steps)
      @random = Random.new(seed)
      @steps = steps
      @counter = 0
      @recorder = Recorder.new { @article&.id }
    end

    def build
      run(:create_article) do
        @article = Article.create!(title: "Root", status: "draft", body: "Start",
                                   metadata: { "seo" => { "priority" => 1 } })
      end
      run(:create_other) { @other = Article.create!(title: "Other", status: "draft", body: "Other") }
      run(:seed_comment) { @article.comments.create!(author: "Jon Bell", body: "First") }
      run(:seed_author) do
        author = Author.create!(name: "Maya Chen", bio: "Bio")
        Authorship.create!(article: @article, author: author, role: "lead", position: 1)
        Authorship.create!(article: @other, author: author, role: "lead", position: 1)
      end
      checkpoint_transaction
      @steps.times do
        operation = OPERATIONS.sample(random: @random)
        SELF_RECORDED.include?(operation) ? send(operation) : run(operation) { send(operation) }
      end
      checkpoint_transaction
      self
    end

    private

    def run(name, habtm_first: false, &block)
      @recorder.run(name, ACTORS.sample(random: @random), habtm_first: habtm_first, &block)
    end

    def number = (@counter += 1)
    def pick(scope) = scope.order(:id).to_a.sample(random: @random)
    def fresh_article = Article.find(@article.id)
    def checkpoint_transaction = run(:checkpoint) { checkpoint }

    def checkpoint = fresh_article.paper_trail.save_with_version
    def touch_article = fresh_article.touch
    def edit_article = fresh_article.update!(%w[title body].sample(random: @random) => "Edit #{number}")
    def edit_metadata = fresh_article.update!(metadata: { "seo" => { "priority" => number }, "keywords" => %w[a b c].sample(2, random: @random) })
    def add_comment = @article.comments.create!(author: ACTORS.sample(random: @random), body: "Comment #{number}")
    def edit_comment = pick(Comment.where(article_id: @article.id))&.update!(body: "Edited #{number}")
    def destroy_comment = pick(Comment.where(article_id: @article.id))&.destroy!
    def add_reply = pick(Comment.where(article_id: @article.id))&.replies&.create!(responder: ACTORS.sample(random: @random), body: "Reply #{number}")
    def edit_reply = pick(Reply.joins(:comment).where(comments: { article_id: @article.id }))&.update!(body: "Reply edited #{number}")
    def destroy_reply = pick(Reply.joins(:comment).where(comments: { article_id: @article.id }))&.destroy!
    def add_author = Authorship.create!(article: @article, author: Author.create!(name: "Author #{number}", bio: "Bio"), role: "contributor", position: number)
    def edit_author = pick(Author.where(id: Authorship.where(article_id: @article.id).select(:author_id)))&.update!(bio: "Bio edited #{number}")
    def edit_authorship = pick(Authorship.where(article_id: @article.id))&.update!(role: "editor", position: number, credited_as: "Credit #{number}")
    def destroy_authorship = pick(Authorship.where(article_id: @article.id))&.destroy!
    def edit_tag = pick(Tag.where(id: fresh_article.tags.select(:id)))&.update!(description: "Described #{number}")
    def add_revision = @article.document_revisions.create!(label: "Doc #{number}")
    def relabel_revision = pick(DocumentRevision.where(attachable: @article))&.update!(label: "Relabelled #{number}")
    def destroy_revision = pick(DocumentRevision.where(attachable: @article))&.destroy!
    def edit_other_article = Article.find(@other.id).update!(title: "Other #{number}")

    def attach_shared_author
      author = pick(Author.where.not(id: Authorship.where(article_id: @article.id).select(:author_id)))
      return add_author unless author

      Authorship.create!(article: @article, author: author, role: "guest", position: number)
    end

    def attach_file
      revision = pick(DocumentRevision.where(attachable: @article)) || @article.document_revisions.create!(label: "File #{number}")
      revision.file.attach(io: StringIO.new("contents #{number}"), filename: "file-#{number}.txt", content_type: "text/plain")
    end

    # DemoHistory's one-pass save: the article and two comments together.
    def save_in_one_pass
      fresh_article.update!(body: "One pass #{number}")
      pick(Comment.where(article_id: @article.id))&.update!(body: "Same pass #{number}")
      @article.comments.create!(author: "Priya Shah", body: "Added in the same pass #{number}")
    end

    # As TaggingsController does: a checkpoint, the change, a checkpoint, each
    # its own transaction. These take no block of their own.
    def attach_tag(tag = nil)
      tag ||= pick(Tag.where.not(id: fresh_article.tags.select(:id)))
      return unless tag

      tag_change { fresh_article.tags << tag }
    end

    def attach_new_tag
      tag = nil
      run(:create_tag) { tag = Tag.create!(name: "Tag #{number}", description: "New") }
      attach_tag(tag)
    end

    def detach_tag
      tag = pick(fresh_article.tags)
      tag_change { fresh_article.tags.delete(tag) } if tag
    end

    def tag_change(&change)
      checkpoint_transaction
      run(:tag_change, &change)
      checkpoint_transaction
    end

    # One transaction that creates and attaches a tag, then checkpoints.
    def create_and_attach_tag_with_checkpoint
      run(:create_and_attach_tag_with_checkpoint, habtm_first: true) do
        fresh_article.tags << Tag.create!(name: "Tag #{number}", description: "With its checkpoint")
        checkpoint
      end
    end
  end

  # Compares every reconstruction of one history with its recorded states.
  class Checker
    attr_reader :failures, :checks

    def initialize(history)
      @recorder = history.recorder
      @article = Article.find(history.article.id)
      @failures = []
      @checks = 0
    end

    def check(label, expected, actual)
      @checks += 1
      found = HistoryOracle.difference(expected, actual)
      @failures << "#{label}: #{found}" if found
    end

    def versions = @article.versions.reorder(:created_at, :id).to_a

    # From every article version to now, and between sampled pairs.
    def endpoints(random)
      versions.each do |from|
        analysis = PaperTrailDiff.analyze(@article, from: from, to: @article, associations: PATHS)
        check("analyze from v#{from.id}: from", @recorder.expected(from), HistoryOracle.snapshot(analysis.from_snapshot))
        check("analyze from v#{from.id}: to", @recorder.final.state, HistoryOracle.snapshot(analysis.to_snapshot))
        check("compare v#{from.id}..now", analysis.diff.to_h,
              PaperTrailDiff.compare(from, @article, associations: PATHS).to_h)
      end
      versions.combination(2).to_a.sample(30, random: random).each do |from, to|
        analysis = PaperTrailDiff.analyze(@article, from: from, to: to, associations: PATHS)
        check("analyze v#{from.id}..v#{to.id}: to", @recorder.expected(to), HistoryOracle.snapshot(analysis.to_snapshot))
      end
    end

    # Each activity step from the first article version to now.
    def activity(group: nil)
      steps = PaperTrailDiff.activity_timeline(@article, from: versions.first, to: @article,
                                               associations: ACTIVITY_PATHS, snapshots: true, group: group)
      names = ACTIVITY_PATHS.map { |path| path.split(".").first }
      steps.each_with_index do |step, index|
        { from: step.from_boundary, to: step.to_boundary }.each do |side, boundary|
          expected = expected_at(boundary)
          next if expected == :skip

          actual = side == :from ? step.from_snapshot : step.to_snapshot
          check("activity (group: #{group.inspect}) step #{index} #{side}",
                HistoryOracle.restrict(expected, names), HistoryOracle.snapshot(actual))
        end
      end
    end

    # The batch path over a window against the single-record path.
    def report_window(random)
      since = @recorder.entries.drop(5).sample(random: random).after
      single = PaperTrailDiff.activity_timeline(@article, within: since..Time.current, associations: ACTIVITY_PATHS)
      report = PaperTrailDiff.report(Article.where(id: @article.id), since: since,
                                     associations: ACTIVITY_PATHS, limit: 10)
      batch = report.analyses.fetch([ "Article", @article.id.to_s ], nil)&.activity_timeline || []
      check("report since #{since.iso8601(6)}", single.map { |step| step.diff.to_h }, batch.map { |step| step.diff.to_h })
    end

    private

    # A version after the first in its transaction stands for a state inside
    # it, which nothing recorded.
    def expected_at(boundary)
      return @recorder.final.state if boundary.current?
      return :skip unless boundary.version_id && @recorder.first_of_transaction?(boundary.version_id)

      @recorder.expected(PaperTrail::Version.find(boundary.version_id))
    end
  end
end
