# Turns activity steps into sentences. Build the steps with `snapshots: true`:
# naming *whose* comment changed needs the record's unchanged fields, which a
# diff does not carry.
class NarrativeTimeline
  MissingSnapshot = Class.new(StandardError)

  Detail = Data.define(:label, :body, :tone)
  Item = Data.define(:kind, :sentence, :details)
  Event = Data.define(:boundary, :visible_by, :items)

  def initialize(steps)
    @steps = steps
  end

  def call
    @steps.filter_map do |step|
      entries = narrative_entries(step.diff)
      items = entries.filter_map { |entry| item_for(entry, step, entries) }
      next if items.empty?

      Event.new(
        boundary: step.from_boundary,
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

  def item_for(entry, step, entries)
    return if duplicate_authorship_membership?(entry, entries)

    case entry.kind
    when :attribute_changed
      attribute_item(entry, step)
    when :record_added
      membership_item(entry, step, :added)
    when :record_removed
      membership_item(entry, step, :removed)
    when :record_presence_changed
      presence_item(entry, step.from_boundary)
    when :relationship_added, :relationship_removed, :relationship_replaced
      relationship_item(entry, step.from_boundary)
    end
  end

  # A join row and the record it credits both surface as additions, so the join
  # is dropped in favour of the sentence about the author. That pairing is
  # one-to-one only because authorships are unique per [article, author]; drop
  # that index and this would silently swallow the extra credits.
  def duplicate_authorship_membership?(entry, entries)
    return false unless entry.record&.type == "Authorship"
    return false unless %i[record_added record_removed].include?(entry.kind)

    entries.any? do |candidate|
      candidate.kind == entry.kind && candidate.record&.type == "Author"
    end
  end

  def attribute_item(entry, step)
    boundary = step.from_boundary
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
      authorship_attribute_item(entry.attribute, change, actor, record)
    when "Tag"
      tag_attribute_item(entry.attribute, change, actor, record)
    else
      changed_attribute_item(actor, type, entry.attribute, change)
    end
  end

  def article_attribute_item(attribute, change, actor)
    sentence = case attribute
    when "status"
      "#{actor} changed the status from `#{change.from}` to `#{change.to}`."
    when "title"
      "#{actor} changed the article title."
    when "body"
      "#{actor} revised the article body."
    else
      "#{actor} changed the article's `#{attribute.humanize.downcase}`."
    end

    item(:attribute_changed, sentence, change_details(attribute, change))
  end

  def comment_attribute_item(entry, change, actor, record)
    author = attribute_of(record, "author") || "an unknown commenter"
    action = actor == author ? "edited their comment" : "edited the comment by #{author}"
    sentence = if entry.attribute == "body"
      "#{actor} #{action}."
    else
      "#{actor} changed `#{entry.attribute.humanize.downcase}` on the comment by #{author}."
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

    item(:reply_changed, "#{actor} edited #{action} to #{recipient}.", details)
  end

  def author_attribute_item(attribute, change, actor, record)
    name = attribute_of(record, "name") || "an author"
    subject = actor == name ? "their author profile" : "#{name}'s author profile"
    sentence = if attribute == "bio"
      "#{actor} updated #{subject}."
    else
      "#{actor} changed `#{attribute.humanize.downcase}` on #{subject}."
    end

    item(:author_changed, sentence, change_details(attribute, change))
  end

  def authorship_attribute_item(attribute, change, actor, record)
    author = record&.associations&.[]("author")&.records&.first
    name = attribute_of(author, "name") || "an author"
    sentence = "#{actor} changed #{name}'s `#{attribute.humanize.downcase}` credit " \
      "from `#{change.from}` to `#{change.to}`."
    item(:authorship_changed, sentence)
  end

  def tag_attribute_item(attribute, change, actor, record)
    name = attribute_of(record, "name") || "an unnamed tag"
    sentence = "#{actor} changed `#{attribute.humanize.downcase}` on the `#{name}` tag."
    item(:tag_changed, sentence, change_details(attribute, change))
  end

  def changed_attribute_item(actor, type, attribute, change)
    sentence = "#{actor} changed `#{attribute.humanize.downcase}` on #{type.underscore.humanize.downcase}."
    item(:attribute_changed, sentence, change_details(attribute, change))
  end

  def membership_item(entry, step, state)
    boundary = step.from_boundary
    snapshot = entry.value
    actor = actor_name(boundary)

    case snapshot.type
    when "Comment"
      comment_membership_item(snapshot, actor, state)
    when "Reply"
      reply_membership_item(entry, snapshot, actor, state, step)
    when "Author"
      author_membership_item(snapshot, actor, state)
    when "Authorship"
      authorship_membership_item(snapshot, actor, state)
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
    sentence = if state == :added
      actor == responder ? "#{responder} replied to #{recipient}." :
        "#{actor} added a reply from #{responder} to #{recipient}."
    elsif actor == responder
      "#{responder} removed their reply to #{recipient}."
    else
      "#{actor} removed #{responder}'s reply to #{recipient}."
    end

    item("reply_#{state}".to_sym, sentence, details)
  end

  def author_membership_item(snapshot, actor, state)
    name = snapshot.attributes["name"].presence || "an unnamed author"
    verb = state == :added ? "added" : "removed"
    direction = state == :added ? "to" : "from"
    details = []
    if snapshot.attributes["bio"].present?
      details << detail("About #{name}", snapshot.attributes["bio"], state)
    end

    item("author_#{state}".to_sym, "#{actor} #{verb} #{name} as an author #{direction} the article.", details)
  end

  def authorship_membership_item(snapshot, actor, state)
    author = snapshot.associations["author"]&.records&.first
    name = author&.attributes&.fetch("name", nil).presence || "an author"
    role = snapshot.attributes["role"].presence
    verb = state == :added ? "credited" : "removed the credit for"
    suffix = role ? " as `#{role}`" : ""

    item("authorship_#{state}".to_sym, "#{actor} #{verb} #{name}#{suffix}.")
  end

  def tag_membership_item(snapshot, actor, state)
    name = snapshot.attributes["name"].presence || "an unnamed tag"
    verb = state == :added ? "added" : "removed"
    direction = state == :added ? "to" : "from"
    details = []
    if snapshot.attributes["description"].present?
      details << detail("About `#{name}`", snapshot.attributes["description"], state)
    end

    item("tag_#{state}".to_sym, "#{actor} #{verb} the `#{name}` tag #{direction} the article.", details)
  end

  def generic_membership_item(snapshot, actor, state)
    verb = state == :added ? "added" : "removed"
    item("record_#{state}".to_sym, "#{actor} #{verb} #{snapshot.type} ##{snapshot.id}.")
  end

  def presence_item(entry, boundary)
    change = entry.value
    actor = actor_name(boundary)
    snapshot = change.to || change.from
    title = snapshot&.attributes&.fetch("title", nil).presence

    if change.to
      sentence = "#{actor} created the article#{" `#{title}`" if title}."
      item(:article_created, sentence)
    else
      sentence = "#{actor} removed the article#{" `#{title}`" if title}."
      item(:article_removed, sentence)
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

  def change_details(attribute, change)
    label = attribute.humanize
    [
      detail("Previous #{label.downcase}", change.from, :before),
      detail("New #{label.downcase}", change.to, :after)
    ]
  end

  def detail(label, body, tone)
    Detail.new(label:, body:, tone:)
  end

  def item(kind, sentence, details = [])
    Item.new(kind:, sentence:, details: details.freeze)
  end
end
