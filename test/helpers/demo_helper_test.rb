require "test_helper"

class DemoHelperTest < ActionView::TestCase
  tests DemoHelper

  def snippet(code, language: :ruby)
    DemoSource::Snippet.new(key: "x.y", layer: "y", path: "p", language:, code:)
  end

  test "marks gem calls and leaves ordinary code alone" do
    html = demo_source_html(snippet("analysis = PaperTrailDiff.analyze(record)\nlocal = record.title"))

    assert_includes html, %(<span class="src-gem">PaperTrailDiff</span>)
    assert_includes html, "local = record.title"
    refute_includes html, %(<span class="src-gem">record.title)
  end

  test "marks whole-line and trailing comments" do
    html = demo_source_html(snippet("# why this exists\nvalue = call # what it feeds"))

    assert_includes html, %(<span class="src-comment"># why this exists</span>)
    assert_includes html, %(<span class="src-comment"> # what it feeds</span>)
  end

  test "carries an ERB comment across the lines it wraps" do
    code = "<%# first line of prose\n    second line of prose %>\n<%= render \"x\" %>"

    html = demo_source_html(snippet(code, language: :erb))

    assert_equal 2, html.scan("src-comment").length, "both comment lines should be marked"
    assert_includes html, "render"
  end

  test "escapes the source before marking it up" do
    html = demo_source_html(snippet(%(tag = "<script>alert(1)</script>")))

    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
  end
end
