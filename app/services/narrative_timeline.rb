# Turns activity steps into sentences. Build the steps with `snapshots: true`:
# naming *whose* comment changed needs the record's unchanged fields, which a
# diff does not carry.
class NarrativeTimeline
  MissingSnapshot = Class.new(StandardError)

  # A sentence is prose with record values set apart as segments, so the view
  # never has to recover which words are data. A title containing a backtick
  # stays one value instead of breaking the markup around it.
  Segment = Data.define(:text, :code)
  Sentence = Data.define(:segments) do
    def to_s = segments.map(&:text).join
  end

  MEMBERSHIP_KINDS = %i[record_added record_removed].freeze
  LABEL_ATTRIBUTES = %w[label name title].freeze
  # `credited_as` humanizes to "credited as", which reads badly before "credit".
  CREDIT_LABELS = { "credited_as" => "byline" }.freeze

  Credits = Data.define(:joins, :authors) do
    def role_for(kind, author_id)
      joins[[ kind, author_id ]]&.attributes&.[]("role").presence
    end

    def narrated_with_author?(kind, join)
      authors.include?([ kind, Credits.author_id(join) ])
    end

    # A selected `authorships.author` path nests the author in the join and
    # leaves its foreign key out of the attributes.
    def self.author_id(join)
      join.associations["author"]&.records&.first&.id || join.attributes["author_id"]
    end
  end
  private_constant :Credits

  Detail = Data.define(:label, :body, :tone)
  Item = Data.define(:kind, :sentence, :details)
  Event = Data.define(:boundary, :visible_by, :items)

  def initialize(steps)
    @steps = steps
  end

  def call
    @steps.filter_map do |step|
      entries = narrative_entries(step.diff)
      credits = authorship_credits(entries)
      items = entries.filter_map { |entry| item_for(entry, step, credits) }
      next if items.empty?

      Event.new(
        boundary: step.source_boundary,
        visible_by: step.to_boundary,
        items: items.freeze
      )
    end.freeze
  end

  private

  def narrative_entries(diff)
    diff.each_change
      .select(&:change?)
      .reject { |entry| entry.kind == :record_changed }
      .uniq { |entry| entry_key(entry) }
  end

  def entry_key(entry)
    record = entry.record
    value = entry.value.respond_to?(:to_h) ? entry.value.to_h : entry.value
    [ entry.kind, record&.type, record&.id, entry.attribute, value ]
  end

  def item_for(entry, step, credits)
    case entry.kind
    when :attribute_changed
      attribute_item(entry, step)
    when :record_added
      membership_item(entry, step, :added, credits)
    when :record_removed
      membership_item(entry, step, :removed, credits)
    when :record_presence_changed
      presence_item(entry, step.source_boundary)
    when :relationship_added, :relationship_removed, :relationship_replaced
      relationship_item(entry, step.source_boundary)
    end
  end

  # Adding an author adds the author and the join row that credits them, so
  # both arrive in one step. The join rows are indexed by the author they
  # credit: the sentence about that author carries the join's role, and only a
  # join with no author sentence of its own is narrated separately.
  def authorship_credits(entries)
    joins = {}
    authors = Set.new
    entries.each do |entry|
      next unless MEMBERSHIP_KINDS.include?(entry.kind)

      case entry.value.type
      when "Authorship" then joins[[ entry.kind, Credits.author_id(entry.value) ]] = entry.value
      when "Author" then authors << [ entry.kind, entry.value.id ]
      end
    end

    Credits.new(joins:, authors:)
  end

  def attribute_item(entry, step)
    boundary = step.source_boundary
    change = entry.value
    actor = actor_name(boundary)
    type = entry.record&.type || boundary.item_type
    record = record_in(step.from_snapshot, entry.association_path, entry.record_path)

    case type
    when "Article"
      article_attribute_item(entry.attribute, change, actor)
    when "Comment"
      comment_attribute_item(entry, change, actor, record)
    when "Reply"
      reply_attribute_item(entry, change, actor, record, step)
    when "Author"
      author_attribute_item(entry.attribute, change, actor, record)
    when "Authorship"
      authorship_attribute_item(entry, change, actor, record, step)
    when "Tag"
      tag_attribute_item(entry.attribute, change, actor, record)
    else
      changed_attribute_item(actor, type, entry.attribute, change, record)
    end
  end

  def article_attribute_item(attribute, change, actor)
    sentence = case attribute
    when "status"
      phrase("#{actor} changed the status from ", code(change.from), " to ", code(change.to), ".")
    when "title"
      "#{actor} changed the article title."
    when "body"
      "#{actor} revised the article body."
    else
      phrase("#{actor} changed the article's ", code(attribute.humanize.downcase), ".")
    end

    item(:attribute_changed, sentence, change_details(attribute, change))
  end

  def comment_attribute_item(entry, change, actor, record)
    author = attribute_of(record, "author") || "an unknown commenter"
    action = actor == author ? "edited their comment" : "edited the comment by #{author}"
    sentence = if entry.attribute == "body"
      "#{actor} #{action}."
    else
      phrase("#{actor} changed ", code(entry.attribute.humanize.downcase), " on the comment by #{author}.")
    end

    item(:comment_changed, sentence, change_details(entry.attribute, change))
  end

  def reply_attribute_item(entry, change, actor, record, step)
    responder = attribute_of(record, "responder") || "an unknown responder"
    parent = parent_comment(entry, step)
    recipient = attribute_of(parent, "author") || "the commenter"
    action = actor == responder ? "their reply" : "the reply by #{responder}"
    parent_body = attribute_of(parent, "body")
    details = []
    details << detail("#{recipient}'s comment", parent_body, :context) if parent_body
    details.concat(change_details(entry.attribute, change))
    addressee = addressee(recipient, responder, actor)

    item(:reply_changed, "#{actor} edited #{action} to #{addressee}.", details)
  end

  def author_attribute_item(attribute, change, actor, record)
    name = attribute_of(record, "name") || "an author"
    subject = actor == name ? "their author profile" : "#{name}'s author profile"
    sentence = if attribute == "bio"
      "#{actor} updated #{subject}."
    else
      phrase("#{actor} changed ", code(attribute.humanize.downcase), " on #{subject}.")
    end

    item(:author_changed, sentence, change_details(attribute, change))
  end

  def authorship_attribute_item(entry, change, actor, record, step)
    name = attribute_of(credited_author(entry, record, step), "name") || "an author"
    possessive = actor == name ? "their own" : "#{name}'s"
    label = CREDIT_LABELS.fetch(entry.attribute, entry.attribute.humanize.downcase)
    sentence = phrase(
      "#{actor} changed #{possessive} ", code(label), " credit from ",
      code(change.from), " to ", code(change.to), "."
    )
    item(:authorship_changed, sentence)
  end

  # The join row reaches the author three ways, depending on the path that
  # surfaced it: nested under it (`authorships.author`), above it
  # (`authors.authorships`), or only as `author_id`.
  def credited_author(entry, record, step)
    nested = record&.associations&.[]("author")&.records&.first
    return nested if nested

    depth = entry.record_path.rindex { |reference| reference.type == "Author" }
    return record_in(step.from_snapshot, entry.association_path.first(depth + 1), entry.record_path) if depth

    author_id = record && Credits.author_id(record)
    step.from_snapshot&.associations&.[]("authors")&.records&.find { |author| author.id == author_id }
  end

  def tag_attribute_item(attribute, change, actor, record)
    name = attribute_of(record, "name") || "an unnamed tag"
    sentence = phrase("#{actor} changed ", code(attribute.humanize.downcase), " on the ", code(name), " tag.")
    item(:tag_changed, sentence, change_details(attribute, change))
  end

  def changed_attribute_item(actor, type, attribute, change, record)
    noun = type.underscore.humanize.downcase
    label = record_label(record)
    target = label ? [ " on the ", code(label), " #{noun}." ] : [ " on #{noun}." ]
    sentence = phrase("#{actor} changed ", code(attribute.humanize.downcase), *target)
    item(:attribute_changed, sentence, change_details(attribute, change))
  end

  def membership_item(entry, step, state, credits)
    boundary = step.source_boundary
    snapshot = entry.value
    actor = actor_name(boundary)

    case snapshot.type
    when "Comment"
      comment_membership_item(snapshot, actor, state)
    when "Reply"
      reply_membership_item(entry, snapshot, actor, state, step)
    when "Author"
      author_membership_item(snapshot, actor, state, credits.role_for(entry.kind, snapshot.id))
    when "Authorship"
      authorship_membership_item(snapshot, actor, state) unless credits.narrated_with_author?(entry.kind, snapshot)
    when "Tag"
      tag_membership_item(snapshot, actor, state)
    else
      generic_membership_item(snapshot, actor, state)
    end
  end

  def comment_membership_item(snapshot, actor, state)
    author = snapshot.attributes["author"].presence || actor
    body = snapshot.attributes["body"]
    tone = state == :added ? :added : :removed
    label = state == :added ? "#{author}'s comment" : "Removed comment by #{author}"
    sentence = if state == :added
      actor == author ? "#{author} commented on the article." : "#{actor} added a comment by #{author}."
    elsif actor == author
      "#{author} removed their comment from the article."
    else
      "#{actor} removed #{author}'s comment from the article."
    end

    item("comment_#{state}".to_sym, sentence, [ detail(label, body, tone) ])
  end

  def reply_membership_item(entry, snapshot, actor, state, step)
    responder = snapshot.attributes["responder"].presence || actor
    parent = parent_comment(entry, step)
    recipient = attribute_of(parent, "author") || "the commenter"
    parent_body = attribute_of(parent, "body")
    details = []
    details << detail("#{recipient}'s comment", parent_body, :context) if parent_body
    label = state == :added ? "#{responder}'s reply" : "Removed reply by #{responder}"
    tone = state == :added ? :added : :removed
    details << detail(label, snapshot.attributes["body"], tone)
    addressee = addressee(recipient, responder, actor)
    sentence = if state == :added
      actor == responder ? "#{responder} replied to #{addressee}." :
        "#{actor} added a reply from #{responder} to #{addressee}."
    elsif actor == responder
      "#{responder} removed their reply to #{addressee}."
    else
      "#{actor} removed #{responder}'s reply to #{addressee}."
    end

    item("reply_#{state}".to_sym, sentence, details)
  end

  def author_membership_item(snapshot, actor, state, role)
    name = snapshot.attributes["name"].presence || "an unnamed author"
    subject = reflexive(actor, name)
    details = []
    if snapshot.attributes["bio"].present?
      details << detail("About #{name}", snapshot.attributes["bio"], state)
    end

    sentence = if state == :removed
      phrase("#{actor} removed #{subject} as an author from the article.")
    elsif role
      phrase("#{actor} added #{subject} as an author to the article, credited as ", code(role), ".")
    else
      phrase("#{actor} added #{subject} as an author to the article.")
    end

    item("author_#{state}".to_sym, sentence, details)
  end

  def authorship_membership_item(snapshot, actor, state)
    author = snapshot.associations["author"]&.records&.first
    name = reflexive(actor, author&.attributes&.fetch("name", nil).presence || "an author")
    role = snapshot.attributes["role"].presence
    verb = state == :added ? "credited" : "removed the credit for"
    suffix = role ? [ " as ", code(role) ] : []

    item("authorship_#{state}".to_sym, phrase("#{actor} #{verb} #{name}", *suffix, "."))
  end

  def tag_membership_item(snapshot, actor, state)
    name = snapshot.attributes["name"].presence || "an unnamed tag"
    verb = state == :added ? "added" : "removed"
    direction = state == :added ? "to" : "from"
    details = []
    if snapshot.attributes["description"].present?
      details << detail(phrase("About ", code(name)), snapshot.attributes["description"], state)
    end

    sentence = phrase("#{actor} #{verb} the ", code(name), " tag #{direction} the article.")
    item("tag_#{state}".to_sym, sentence, details)
  end

  def generic_membership_item(snapshot, actor, state)
    verb = state == :added ? "added" : "removed"
    noun = snapshot.type.underscore.humanize.downcase
    label = record_label(snapshot)
    sentence = if label
      phrase("#{actor} #{verb} the ", code(label), " #{noun}.")
    else
      phrase("#{actor} #{verb} #{noun} ##{snapshot.id}.")
    end

    item("record_#{state}".to_sym, sentence)
  end

  def presence_item(entry, boundary)
    change = entry.value
    actor = actor_name(boundary)
    snapshot = change.to || change.from
    title = snapshot&.attributes&.fetch("title", nil).presence
    named = title ? [ " ", code(title) ] : []

    if change.to
      item(:article_created, phrase("#{actor} created the article", *named, "."))
    else
      item(:article_removed, phrase("#{actor} removed the article", *named, "."))
    end
  end

  def relationship_item(entry, boundary)
    actor = actor_name(boundary)
    association = entry.association.to_s.humanize.downcase
    action = entry.kind.to_s.delete_prefix("relationship_").humanize.downcase
    item(entry.kind, "#{actor} #{action} the article's #{association} relationship.")
  end

  def parent_comment(entry, step)
    depth = entry.record_path.rindex { |record| record.type == "Comment" }
    return unless depth

    record_in(step.from_snapshot, entry.association_path.first(depth + 1), entry.record_path)
  end

  # Walks the reconstructed state the gem already built for this boundary. The
  # snapshot is the root record with its selected associations nested inside, so
  # following the entry's association path lands on the record that changed --
  # no version queries, and no reimplementation of boundary semantics.
  def record_in(snapshot, association_path, record_path)
    if snapshot.nil? && association_path.any?
      # A nested record changed, so the root existed and its state should be
      # here. Missing means the steps were built without `snapshots: true`, and
      # degrading to "an unknown commenter" would hide that.
      raise MissingSnapshot, "activity steps must be built with snapshots: true"
    end

    association_path.each_with_index.reduce(snapshot) do |current, (name, index)|
      reference = record_path[index]
      break nil unless current && reference

      current.associations[name]&.records&.find do |candidate|
        candidate.type == reference.type && candidate.id == reference.id
      end
    end
  end

  def attribute_of(snapshot, name)
    snapshot&.attributes&.[](name).presence
  end

  def actor_name(boundary)
    boundary.whodunnit.to_s.presence || "Someone"
  end

  # "Luis Ortega added Luis Ortega" reads like a bug, not a self-action.
  def reflexive(actor, name)
    actor == name ? "themselves" : name
  end

  # Likewise "Jon Bell replied to Jon Bell": the reply is to their own comment.
  def addressee(recipient, responder, actor)
    return recipient unless recipient == responder

    actor == responder ? "their own comment" : "#{recipient}'s own comment"
  end

  def record_label(snapshot)
    LABEL_ATTRIBUTES.filter_map { |name| attribute_of(snapshot, name) }.first
  end

  def change_details(attribute, change)
    label = attribute.humanize
    [
      detail("Previous #{label.downcase}", change.from, :before),
      detail("New #{label.downcase}", change.to, :after)
    ]
  end

  def detail(label, body, tone)
    Detail.new(label: phrase(label), body:, tone:)
  end

  def item(kind, sentence, details = [])
    Item.new(kind:, sentence: phrase(sentence), details: details.freeze)
  end

  # Plain strings are prose and `code` marks a value. A finished sentence
  # passes through unchanged, so a builder can hand over either.
  def phrase(*parts)
    return parts.first if parts.one? && parts.first.is_a?(Sentence)

    segments = parts.map { |part| part.is_a?(Segment) ? part : Segment.new(text: part.to_s, code: false) }
    Sentence.new(segments: segments.freeze)
  end

  def code(value)
    Segment.new(text: value.to_s, code: true)
  end
end
