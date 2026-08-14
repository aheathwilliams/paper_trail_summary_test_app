class DemoController < ApplicationController
  CURRENT_ENDPOINT = "current"
  MAX_ASSOCIATION_DEPTH = 2
  ROOT_PATH = "$"

  def show
    @articles = Article.order(:title, :id).to_a
    @article = selected_article
    @new_article = Article.new(status: "draft")
    return unless @article

    @new_comment = Comment.new(article: @article)
    @new_author = Author.new
    @new_authorship = Authorship.new(article: @article, role: "contributor", position: 1)
    @new_tag = Tag.new
    @authorships = @article.authorships.includes(:author).order(:id).to_a
    @available_authors = Author.where.not(id: @article.author_ids).order(:name, :id).to_a
    @tags = @article.tags.order(:name, :id).to_a
    @available_tags = Tag.where.not(id: @article.tag_ids).order(:name, :id).to_a
    @versions = @article.versions.order(:created_at, :id).to_a
    @selectable_versions = @versions
    @version_labels = @selectable_versions.to_h do |version|
      record = version.reify(dup: true)
      label = if record
        "Version #{version.id} · #{record.status.humanize} · #{record.title}"
      else
        "Version #{version.id} · Create boundary · record absent"
      end
      [ version.id, label ]
    end
    @version_options = @selectable_versions.map do |version|
      [ @version_labels.fetch(version.id), version.id ]
    end
    @to_options = [
      *@version_options,
      [ "Current Article · #{@article.status.humanize} · #{@article.title}", CURRENT_ENDPOINT ]
    ]

    update_versions = @versions.reject { |version| version.event == "create" }
    default_from = update_versions.one? ? @versions.first : update_versions.first
    @from_version = selected_version(:from, fallback: default_from || @versions.first)
    @to_endpoint = selected_to_endpoint(fallback: @article)
    @selected_to_value = current_endpoint? ? CURRENT_ENDPOINT : @to_endpoint.id
    @association_options = association_options
    @selected_associations = selected_associations
    @author_options = author_options
    @selected_author = selected_author_filter
    @ignored_attributes = configured_ignored_attributes
    @ignored_paths = configured_ignored_paths
    @ignore_option = configured_ignore_option
    @blacklist_attribute_options = blacklist_attribute_options
    @ignore_path_options = ignore_path_options

    build_comparison if @from_version && @to_endpoint
  rescue PaperTrailDiff::Error, ActiveRecord::RecordNotFound => error
    @comparison_error = error.message
  end

  def reset
    DemoHistory.create!
    redirect_to root_path, notice: "A fresh PaperTrail history was generated."
  end

  private

  def selected_article
    return @articles.last if params[:article_id].blank?

    @articles.find { |article| article.id.to_s == params[:article_id].to_s } || @articles.last
  end

  def selected_version(name, fallback:)
    requested_id = params["#{name}_id"]
    return fallback if requested_id.blank?

    @selectable_versions.find { |version| version.id.to_s == requested_id.to_s } ||
      raise(ActiveRecord::RecordNotFound, "That version is not part of this article.")
  end

  def selected_to_endpoint(fallback:)
    requested_id = params[:to_id]
    return fallback if requested_id.blank?
    return @article if requested_id == CURRENT_ENDPOINT

    @selectable_versions.find { |version| version.id.to_s == requested_id.to_s } ||
      raise(ActiveRecord::RecordNotFound, "That endpoint is not part of this article.")
  end

  def build_comparison
    return build_current_comparison if current_endpoint?

    from_index = @selectable_versions.index(@from_version)
    to_index = @selectable_versions.index(@to_endpoint)
    if from_index > to_index
      @comparison_error = "The start version must come before the end version."
      return
    end

    # demo:code shared.controller
    # One pass over the history produces every view on this page. `scoped_options`
    # carries what the form chose: `associations:`, `ignore:`, and `version_scope:`
    # when a person is selected.
    analysis = PaperTrailDiff.analyze(
      @article,
      from: @from_version,
      to: @to_endpoint,
      **scoped_options,
      activity: true,   # also build the descendant-aware timeline
      snapshots: true   # keep each step's reconstructed state for the narrative
    )
    @diff = analysis.diff       # endpoint and overview tabs
    @steps = analysis.timeline  # checkpoints tab
    # demo:code end
    assign_activity_steps(analysis.activity_timeline)
    @activity_api_label = if @selected_author
      "PaperTrailDiff.analyze(..., activity: true, version_scope: ...)"
    else
      "PaperTrailDiff.analyze(..., activity: true)"
    end
    @diagnostics = PaperTrailDiff.diagnose(
      @from_version,
      @to_endpoint,
      associations: @selected_associations
    )
  end

  def build_current_comparison
    latest_version = @selectable_versions.last
    @diff = PaperTrailDiff.compare(@from_version, @article, **comparison_options)
    @steps = PaperTrailDiff.timeline(
      @article,
      from: @from_version,
      to: latest_version,
      **scoped_options
    )
    assign_current_activity_steps(latest_version)
    @diagnostics = PaperTrailDiff.diagnose(
      @from_version,
      latest_version,
      associations: @selected_associations
    )
  end

  def assign_current_activity_steps(latest_version)
    steps = PaperTrailDiff.activity_timeline(
      @article,
      from: @from_version,
      to: @article,
      **scoped_options,
      snapshots: true
    )
    assign_activity_steps(steps)
    @activity_api_label = "PaperTrailDiff.activity_timeline(..., to: article)"
  rescue PaperTrailDiff::UnsupportedLiveActivityError
    steps = PaperTrailDiff.activity_timeline(
      @article,
      from: @from_version,
      to: latest_version,
      **scoped_options,
      snapshots: true
    )
    assign_activity_steps(steps)
    @activity_api_label = "PaperTrailDiff.activity_timeline(..., to: latest_version)"
    @activity_notice = <<~MESSAGE.squish
      Live activity is unavailable for the selected HABTM graph, so the activity
      views end at Version #{latest_version.id}. The endpoint diff still uses the
      current database state.
    MESSAGE
  end

  def assign_activity_steps(steps)
    @activity_steps = steps
    # demo:code visible.controller
    # A step whose diff is empty is a boundary nothing you selected crossed --
    # a checkpoint, or a change to a field you ignored. Every step type answers
    # `empty?`, so one filter serves both timelines.
    @visible_activity_steps = steps.reject(&:empty?)
    # demo:code end
    # demo:code narratives.controller
    # The narrative reads reconstructed state from each step, which is why the
    # steps above are built with `snapshots: true`.
    @narrative_events = NarrativeTimeline.new(@visible_activity_steps).call
    # demo:code end
  end

  def comparison_options
    { associations: @selected_associations, ignore: @ignore_option }
  end

  # `compare` diffs two endpoints you named yourself, so a filter cannot change
  # its answer and it does not accept one. Only the range-selecting calls take
  # the hook.
  def scoped_options
    return comparison_options unless @selected_author

    comparison_options.merge(version_scope: author_version_scope)
  end

  # The "changes made by one person" report. The hook receives the version
  # relation the range selected and returns a narrowed one, so the filtering
  # happens in SQL rather than over reified snapshots.
  def author_version_scope
    author = @selected_author
    ->(scope) { scope.where(whodunnit: author) }
  end

  def author_options
    @versions.filter_map(&:whodunnit).uniq.sort
  end

  def selected_author_filter
    requested = params[:whodunnit]
    return if requested.blank?

    @author_options.include?(requested) ? requested : nil
  end

  def current_endpoint?
    @to_endpoint.equal?(@article)
  end

  def parse_ignore_list(value)
    Array(value).flat_map { |entry| entry.to_s.split(/[\s,]+/) }
      .reject(&:blank?).uniq.first(20)
  end

  def configured_ignored_attributes
    if params[:blacklist_configured].present? || params.key?(:ignore)
      parse_ignore_list(params[:ignore])
    else
      Rails.configuration.x.paper_trail_diff.default_ignore
    end
  end

  def configured_ignored_paths
    return {} unless params[:blacklist_configured].present? || params.key?(:ignore_paths)

    allowed_paths = [ ROOT_PATH, *expanded_selected_association_paths ]
    path_params = params[:ignore_paths]
    return {} unless path_params.respond_to?(:each_pair)

    path_params.each_pair.with_object({}) do |(path, attributes), configured|
      name = path.to_s
      ignored = parse_ignore_list(attributes)
      configured[name] = ignored if allowed_paths.include?(name) && ignored.any?
    end.sort.to_h
  end

  def configured_ignore_option
    return @ignored_attributes if @ignored_paths.empty?

    { all: @ignored_attributes, paths: @ignored_paths }
  end

  def blacklist_attribute_options
    models = [ Article, *@association_options.map(&:last) ].uniq
    options = models.flat_map do |model|
      attribute_options_for(model).map { |name| [ name, model.model_name.human ] }
    end

    options.group_by(&:first).map do |name, occurrences|
      [ name, occurrences.map(&:last).uniq.sort.join(", ") ]
    end.sort_by(&:first)
  end

  def ignore_path_options
    root = [ ROOT_PATH, "Article root", attribute_options_for(Article) ]
    associations = @association_options.map do |path, _description, model|
      [ path, model.model_name.human, attribute_options_for(model) ]
    end

    [ root, *associations ]
  end

  def attribute_options_for(model)
    model.column_names.reject { |name| name == model.primary_key }.sort
  end

  def association_options
    PaperTrailDiff.association_paths(@article, max_depth: MAX_ASSOCIATION_DEPTH)
      .reject { |descriptor| descriptor.polymorphic || descriptor.cycle || descriptor.target_type.nil? }
      .filter_map do |descriptor|
        model = descriptor.target_type.constantize
        next unless model <= ApplicationRecord

        [ descriptor.path, association_description(descriptor), model ]
      end
  end

  def association_description(descriptor)
    kind = if descriptor.through
      "#{descriptor.kind} through #{descriptor.through}"
    else
      descriptor.kind.to_s
    end
    [ ("nested" if descriptor.path.include?(".")), kind ].compact.join(" · ").humanize
  end

  def selected_associations
    available = @association_options.map(&:first)
    selected = if params[:associations_configured].present?
      parse_ignore_list(params[:associations])
    elsif params[:associations].present?
      legacy_association_selection(params[:associations], available)
    else
      available
    end

    selected & available
  end

  def expanded_selected_association_paths
    @selected_associations.flat_map do |path|
      segments = path.split(".")
      segments.each_index.map { |index| segments.first(index + 1).join(".") }
    end.uniq
  end

  def legacy_association_selection(value, available)
    case value.to_s
    when "all" then available
    when "none" then []
    else parse_ignore_list(value)
    end
  end
end
