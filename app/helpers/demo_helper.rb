module DemoHelper
  ACTIVITY_COUNT_LABELS = {
    fields: [ "field", "fields" ],
    added: [ "added", "added" ],
    removed: [ "removed", "removed" ],
    changed: [ "record changed", "records changed" ],
    relationships: [ "relationship", "relationships" ],
    presence: [ "record state", "record states" ]
  }.freeze

  ACTIVITY_ENTRY_COUNTS = {
    record_presence_changed: :presence,
    attribute_changed: :fields,
    record_added: :added,
    relationship_added: :added,
    record_removed: :removed,
    relationship_removed: :removed,
    record_changed: :changed,
    relationship_replaced: :relationships
  }.freeze

  def activity_change_counts(diff)
    counts = ACTIVITY_COUNT_LABELS.keys.index_with(0)
    diff.each_change do |entry|
      count = ACTIVITY_ENTRY_COUNTS[entry.kind]
      counts[count] += 1 if count
    end
    counts
  end

  def activity_diff_summary(diff)
    items = activity_change_counts(diff).filter_map do |kind, count|
      "#{count} #{activity_count_label(kind, count)}" if count.positive?
    end
    items.presence&.join(" · ") || "No visible change"
  end

  def activity_count_label(kind, count)
    ACTIVITY_COUNT_LABELS.fetch(kind).fetch(count == 1 ? 0 : 1)
  end

  def activity_record_label(record)
    "#{record.type} ##{record.id}"
  end

  def activity_boundary_label(boundary)
    record = activity_record_label(boundary.record)
    return "Current #{record}" if boundary.current?

    "#{record} · version #{boundary.version_id}"
  end

  def activity_boundary_context(boundary)
    [
      boundary.event&.humanize,
      ("by #{boundary.whodunnit}" if boundary.whodunnit.present?),
      activity_boundary_time(boundary)
    ].compact.join(" · ")
  end

  def activity_boundary_time(boundary)
    boundary.recorded_at.strftime("%b %-d, %Y · %-I:%M:%S %p UTC")
  end

  def narrative_sentence(sentence)
    segments = sentence.to_s.split(/(`[^`]*`)/).map do |segment|
      if segment.start_with?("`") && segment.end_with?("`")
        content_tag(:code, segment[1...-1])
      else
        segment
      end
    end

    safe_join(segments)
  end

  def endpoint_attribute_count(diff)
    snapshot = endpoint_presence_snapshot(diff)
    snapshot ? snapshot.attributes.length : diff.attributes.length
  end

  def endpoint_attribute_label(diff)
    change = diff.record_presence_change
    return "attribute changes" unless change

    change.to ? "attributes included" : "attributes removed"
  end

  def endpoint_collection_count(diff, name, state)
    change = diff.record_presence_change
    if change
      lifecycle_state = change.to ? :added : :removed
      return 0 unless state == lifecycle_state

      return endpoint_presence_snapshot(diff).associations[name]&.records&.length || 0
    end

    association = diff.associations[name]
    association ? association.public_send(state).length : 0
  end

  def endpoint_presence_snapshot(diff)
    change = diff.record_presence_change
    change&.to || change&.from
  end

  def activity_value(value)
    text, modifier = case value
    when nil
      [ "None", " activity-value--empty" ]
    when ""
      [ "Empty string", " activity-value--empty" ]
    when Time, Date, DateTime, ActiveSupport::TimeWithZone
      [ value.strftime("%b %-d, %Y · %-I:%M:%S %p UTC"), " activity-value--time" ]
    when PaperTrailDiff::RecordSnapshot, PaperTrailDiff::RecordReference
      [ activity_record_label(value), " activity-value--record" ]
    when Array, Hash
      [ JSON.generate(value.as_json), " activity-value--structured" ]
    else
      [ value.to_s, "" ]
    end

    content_tag(:span, text, class: "activity-value#{modifier}")
  end
end
