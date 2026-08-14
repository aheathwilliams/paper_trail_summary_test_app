require "test_helper"

class DemoSourceTest < ActiveSupport::TestCase
  test "extracts each marked region from the file that defines it" do
    snippet = DemoSource.all.fetch("shared.model")

    assert_equal "app/models/article.rb", snippet.path
    assert_equal "model", snippet.layer
    assert_includes snippet.code, "has_paper_trail"
    # Marked regions live inside a class, so they arrive indented.
    refute snippet.code.start_with?(" "), "expected the snippet to be dedented"
    refute_includes snippet.code, "demo:code"
  end

  test "offers every view the shared model and controller plus its own layers" do
    %w[overview endpoint checkpoints activity visible narratives].each do |view|
      layers = DemoSource.for(view).map(&:key)

      assert_includes layers, "shared.model", "#{view} should show the versioned models"
      assert_includes layers, "shared.controller", "#{view} should show the call that runs"
      assert_includes layers, "#{view}.view", "#{view} should show its own template code"
    end
  end

  test "snippets stay valid code rather than truncated fragments" do
    # A region cut off mid-block would teach something that cannot run, and is
    # the failure mode a hand-copied example has too.
    DemoSource.all.each do |key, snippet|
      next unless snippet.language == :erb

      opens = snippet.code.scan(/<%[-=]?\s*(?:if|unless|.*\bdo\b)/).length
      closes = snippet.code.scan(/<%\s*end\s*[-]?%>/).length
      assert_equal opens, closes, "#{key} has #{opens} ERB blocks but #{closes} ends"
    end
  end

  test "publishes the partials that unpack a diff, not just the page template" do
    keys = DemoSource.for("activity").map(&:key)

    # The template shows the loop; these show how a Diff is actually read,
    # which is the part a reader is looking for.
    assert_includes keys, "shared.diff"
    assert_includes keys, "shared.change"
    assert_includes keys, "shared.association"
    assert_includes DemoSource.all.fetch("shared.diff").code, "diff.associations"
    assert_includes DemoSource.all.fetch("shared.change").code, "change.from"
  end

  test "orders snippets so a reader meets them in reading order" do
    layers = DemoSource.for("activity").map(&:layer)

    assert_equal layers.sort_by { |l| DemoSource::LAYER_ORDER.index(l) }, layers
    assert_equal "model", layers.first
  end

  test "reads from disk so a snippet cannot drift from the code it documents" do
    assert_includes DemoSource::FILES.keys, "app/controllers/demo_controller.rb"

    controller = DemoSource.all.fetch("shared.controller")
    on_disk = Rails.root.join(controller.path).read

    controller.code.lines.map(&:strip).reject(&:empty?).each do |line|
      assert_includes on_disk, line, "snippet line is not present in the real file"
    end
  end
end
