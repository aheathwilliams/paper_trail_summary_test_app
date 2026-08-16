# Extracts the code that produces each result view, straight out of the files
# that produce it. Regions are marked in the real source:
#
#   # demo:code checkpoints.controller
#   ...
#   # demo:code end
#
# so a snippet cannot drift from the behaviour it documents the way a copied
# example would. ERB marks regions with `<%# demo:code ... %>`.
class DemoSource
  Snippet = Data.define(:key, :layer, :path, :language, :code)

  FILES = {
    "app/models/article.rb" => :ruby,
    "app/models/document_revision.rb" => :ruby,
    "app/controllers/demo_controller.rb" => :ruby,
    "app/services/narrative_timeline.rb" => :ruby,
    "app/views/demo/show.html.erb" => :erb,
    "app/views/demo/_activity_diff.html.erb" => :erb,
    "app/views/demo/_activity_attribute_changes.html.erb" => :erb,
    "app/views/demo/_activity_association_diff.html.erb" => :erb
  }.freeze

  # Reading order: the models being versioned, the call that runs, the template
  # that lays the result out, then the partials that unpack the diff itself.
  LAYER_ORDER = %w[model attachment controller view diff change association narrative].freeze

  BEGIN_MARKER = /demo:code\s+(?<key>[a-z_]+\.[a-z_]+)\s*(?:%>)?\s*\z/
  END_MARKER = /demo:code\s+end\s*(?:%>)?\s*\z/

  class << self
    # Snippets for one view in reading order: everything marked `shared.*`
    # plus everything marked for this view. Selecting by prefix rather than an
    # explicit list means marking a new region is enough to publish it.
    def for(view)
      relevant = all.values.select do |snippet|
        snippet.key.start_with?("shared.", "#{view}.")
      end
      relevant.sort_by { |snippet| [LAYER_ORDER.index(snippet.layer) || 99, snippet.key] }
    end

    def all
      return @all if defined?(@all) && @all && !Rails.env.development?

      @all = FILES.each_with_object({}) do |(path, language), found|
        extract(Rails.root.join(path), path, language, found)
      end
    end

    private

    def extract(absolute, path, language, found)
      return unless File.exist?(absolute)

      key = nil
      buffer = []
      File.readlines(absolute, chomp: true).each do |line|
        if key.nil?
          key = line[BEGIN_MARKER, :key]
          buffer = []
        elsif END_MARKER.match?(line)
          found[key] ||= build(key, path, language, buffer)
          key = nil
        else
          buffer << line
        end
      end
    end

    def build(key, path, language, lines)
      Snippet.new(
        key: key,
        layer: key.split(".")[1],
        path: path,
        language: language,
        code: dedent(lines)
      )
    end

    # Marked regions are nested inside classes and templates, so they arrive
    # with the indentation of wherever they live.
    def dedent(lines)
      meaningful = lines.reject { |line| line.strip.empty? }
      return "" if meaningful.empty?

      margin = meaningful.map { |line| line[/\A */].length }.min
      lines.map { |line| line[margin..] || "" }.join("\n").strip
    end
  end
end
