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

  # A key that was absent is not a key set to null: `{"a": null}` and `{}` mean
  # different things in JSON, so the gem gives absence its own value and this
  # renders it as its own thing rather than as "None".
  # One element of an array reported by membership. An element that is itself a
  # structure is shown whole, because the gem does not claim which field of
  # which object changed -- that would need a pairing nothing licenses.
  def nested_element(value)
    case value
    when Hash, Array then JSON.generate(value.as_json)
    when nil then "null"
    else value.to_s
    end
  end

  def nested_value(value)
    if value.equal?(PaperTrailDiff::NestedComparator::ABSENT)
      return tag.span("Not present", class: "activity-value activity-value--empty")
    end

    activity_value(value)
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

  # Emphasises the two things a reader of these snippets is looking for: the
  # calls into the gem, and the prose explaining why they are there. Deliberately
  # not general syntax highlighting -- colouring every token equally would bury
  # the parts that matter.
  GEM_API = Regexp.union(
    /PaperTrailDiff(?:::[A-Za-z_]+)*/,
    /\b(?:associations|ignore|version_scope|snapshots|activity|close_on|within|from|to):/,
    /\.(?:diff|timeline|activity_timeline|attributes|associations|record_presence_change|
         from_boundary|to_boundary|from_snapshot|to_snapshot|added|removed|changed|
         kind|whodunnit|reify|to_h|empty\?)\b/x,
    /\bhas_paper_trail\b/
  ).freeze

  def demo_source_html(snippet)
    in_erb_comment = false
    lines = snippet.code.split("\n").map do |line|
      html, in_erb_comment = demo_source_line(line, snippet.language, in_erb_comment)
      html
    end
    safe_join(lines, "\n")
  end

  private

  def demo_source_line(line, language, in_erb_comment)
    if in_erb_comment
      return [comment_span(line), !line.include?("%>")]
    end
    if language == :erb && line.lstrip.start_with?("<%#")
      return [comment_span(line), !line.include?("%>")]
    end
    return [comment_span(line), false] if line.lstrip.start_with?("#")

    code, trailing = line.split(/(?=\s+#[^"']*\z)/, 2)
    [safe_join([gem_api_html(code.to_s), trailing ? comment_span(trailing) : nil].compact), false]
  end

  def comment_span(text)
    tag.span(text, class: "src-comment")
  end

  # Escape first, then mark up, so nothing in the source can inject markup.
  def gem_api_html(code)
    escaped = ERB::Util.html_escape(code).to_s
    escaped.gsub(GEM_API) { |match| tag.span(match.html_safe, class: "src-gem") }.html_safe
  end
end
