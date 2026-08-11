class NarrativeTimeline
  Detail = Data.define(:label, :body, :tone)
  Item = Data.define(:kind, :sentence, :details)
  Event = Data.define(:boundary, :visible_by, :items)

  def initialize(steps)
    @steps = steps
    @record_cache = {}
  end

  def call
    @steps.filter_map do |step|
      entries = narrative_entries(step.diff)
      items = entries.filter_map { |entry| item_for(entry, step.from_boundary, entries) }
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

  def item_for(entry, boundary, entries)
    return if duplicate_authorship_membership?(entry, entries)

    case entry.kind
    when :attribute_changed
      attribute_item(entry, boundary)
    when :record_added
      membership_item(entry, boundary, :added)
    when :record_removed
      membership_item(entry, boundary, :removed)
    when :record_presence_changed
      presence_item(entry, boundary)
    when :relationship_added, :relationship_removed, :relationship_replaced
      relationship_item(entry, boundary)
    end
  end

  def duplicate_authorship_membership?(entry, entries)
    return false unless entry.record&.type == "Authorship"
    return false unless %i[record_added record_removed].include?(entry.kind)

    entries.any? do |candidate|
      candidate.kind == entry.kind && candidate.record&.type == "Author"
    end
  end

  def attribute_item(entry, boundary)
    change = entry.value
    actor = actor_name(boundary)
    type = entry.record&.type || boundary.item_type
    record = record_at(entry.record, boundary)

    case type
    when "Article"
      article_attribute_item(entry.attribute, change, actor)
    when "Comment"
      comment_attribute_item(entry, change, actor, record)
    when "Reply"
      reply_attribute_item(entry, change, actor, record, boundary)
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
    author = record&.author.presence || "an unknown commenter"
    action = actor == author ? "edited their comment" : "edited the comment by #{author}"
    sentence = if entry.attribute == "body"
      "#{actor} #{action}."
    else
      "#{actor} changed `#{entry.attribute.humanize.downcase}` on the comment by #{author}."
    end

    item(:comment_changed, sentence, change_details(entry.attribute, change))
  end

  def reply_attribute_item(entry, change, actor, record, boundary)
    responder = record&.responder.presence || "an unknown responder"
    parent = parent_comment(entry, boundary)
    recipient = parent&.author.presence || "the commenter"
    action = actor == responder ? "their reply" : "the reply by #{responder}"
    details = []
    details << detail("#{recipient}'s comment", parent.body, :context) if parent&.body.present?
    details.concat(change_details(entry.attribute, change))

    item(:reply_changed, "#{actor} edited #{action} to #{recipient}.", details)
  end

  def author_attribute_item(attribute, change, actor, record)
    name = record&.name.presence || "an author"
    subject = actor == name ? "their author profile" : "#{name}'s author profile"
    sentence = if attribute == "bio"
      "#{actor} updated #{subject}."
    else
      "#{actor} changed `#{attribute.humanize.downcase}` on #{subject}."
    end

    item(:author_changed, sentence, change_details(attribute, change))
  end

  def authorship_attribute_item(attribute, change, actor, record)
    author = record&.author
    name = author&.name.presence || "an author"
    sentence = "#{actor} changed #{name}'s `#{attribute.humanize.downcase}` credit " \
      "from `#{change.from}` to `#{change.to}`."
    item(:authorship_changed, sentence)
  end

  def tag_attribute_item(attribute, change, actor, record)
    name = record&.name.presence || "an unnamed tag"
    sentence = "#{actor} changed `#{attribute.humanize.downcase}` on the `#{name}` tag."
    item(:tag_changed, sentence, change_details(attribute, change))
  end

  def changed_attribute_item(actor, type, attribute, change)
    sentence = "#{actor} changed `#{attribute.humanize.downcase}` on #{type.underscore.humanize.downcase}."
    item(:attribute_changed, sentence, change_details(attribute, change))
  end

  def membership_item(entry, boundary, state)
    snapshot = entry.value
    actor = actor_name(boundary)

    case snapshot.type
    when "Comment"
      comment_membership_item(snapshot, actor, state)
    when "Reply"
      reply_membership_item(entry, snapshot, actor, state, boundary)
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

  def reply_membership_item(entry, snapshot, actor, state, boundary)
    responder = snapshot.attributes["responder"].presence || actor
    parent = parent_comment(entry, boundary)
    recipient = parent&.author.presence || "the commenter"
    details = []
    details << detail("#{recipient}'s comment", parent.body, :context) if parent&.body.present?
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

  def parent_comment(entry, boundary)
    reference = entry.record_path.reverse.find { |record| record.type == "Comment" }
    record_at(reference, boundary)
  end

  def record_at(reference, boundary)
    return unless reference

    key = [ reference.type, reference.id, boundary.version_id || :current ]
    @record_cache[key] ||= begin
      model = reference.type.safe_constantize
      if model && model < ApplicationRecord
        current = model.find_by(id: reference.id)
        if boundary.current?
          current
        else
          versions = PaperTrail::Version.where(item_type: model.base_class.name, item_id: reference.id)
          later = versions.where(
            "created_at > :time OR (created_at = :time AND id > :id)",
            time: boundary.recorded_at,
            id: boundary.version_id
          ).order(:created_at, :id).first

          later&.reify || current || versions.order(:created_at, :id).last&.reify
        end
      end
    end
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
