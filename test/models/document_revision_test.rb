require "test_helper"

class DocumentRevisionTest < ActiveSupport::TestCase
  setup do
    @article = Article.create!(title: "Budget", status: "draft", body: "b")
    @revision = @article.document_revisions.create!(label: "Budget plan")
  end

  def attach(name, body)
    @revision.file.attach(io: StringIO.new(body), filename: name, content_type: "text/plain")
    @revision.reload
  end

  test "mirrors blob metadata onto versioned columns" do
    attach("budget-v1.txt", "first pass")

    assert_equal "budget-v1.txt", @revision.filename
    assert_equal "text/plain", @revision.content_type
    assert_equal "first pass".bytesize, @revision.byte_size
    assert @revision.checksum.present?
  end

  test "records a version for the mirrored change" do
    # The point of mirroring: attaching writes to ActiveStorage's tables and
    # nothing here, so without a versioned write there is no history at all.
    # `update_columns` would skip PaperTrail's callbacks and audit nothing.
    before = @revision.versions.count
    attach("budget-v1.txt", "first pass")

    assert_operator @revision.versions.count, :>, before
    assert @revision.versions.any? { |v| v.changeset.key?("filename") },
           "expected a version recording the filename"
  end

  test "stops rather than looping when the metadata already matches" do
    attach("budget-v1.txt", "first pass")
    settled = @revision.versions.count

    @revision.reload.save!

    assert_equal settled, @revision.versions.reload.count
  end

  test "a replacement is visible to the gem as an ordinary versioned change" do
    attach("budget-v1.txt", "first pass")
    @article.reload
    Article.transaction { Article.find(@article.id).paper_trail.save_with_version }
    before = @article.versions.reload.last

    attach("budget-v2.txt", "second pass, longer")
    @article.reload
    Article.transaction { Article.find(@article.id).paper_trail.save_with_version }
    after = @article.versions.reload.last

    diff = PaperTrailDiff.compare(before, after, associations: [ "document_revisions" ])
    changed = diff.associations["document_revisions"].changed.first

    assert_equal({ from: "budget-v1.txt", to: "budget-v2.txt" },
                 changed.attributes.fetch("filename").to_h)
    assert changed.attributes.key?("checksum"), "the checksum should move with the file"
  end

  test "the gem refuses the ActiveStorage association itself" do
    # This app installs the published gem, so the check activates when the
    # release carrying it lands rather than being asserted against a working
    # copy nobody else has.
    unless defined?(PaperTrailDiff::UnversionedAssociationError)
      skip "requires a paper_trail_diff release with UnversionedAssociationError"
    end

    attach("budget-v1.txt", "first pass")
    versions = @revision.versions.reload.to_a

    # ActiveStorage::Attachment is not versioned, so there is no history behind
    # it. Refusing beats reporting that nothing changed.
    error = assert_raises(PaperTrailDiff::UnversionedAssociationError) do
      PaperTrailDiff.compare(versions.first, versions.last, associations: [ "file_attachment" ])
    end
    assert_match(/not versioned/, error.message)
  end
  test "file metadata is audited once per upload under the submitting actor" do
    PaperTrail.request(whodunnit: "Uploader") do
      @created = @article.document_revisions.create!(
        label: "One save", file: { io: StringIO.new("first"), filename: "first.txt", content_type: "text/plain" }
      )
    end
    creation = @created.versions.find_by!(event: "create")
    assert_equal "Uploader", creation.whodunnit
    assert_equal [ nil, "first.txt" ], creation.changeset.fetch("filename")
    # ActiveStorage may touch its owner after attaching and analyzing a blob.
    # Those empty versions must not become a second metadata update.
    assert_equal 1, @created.versions.count { |version| version.changeset.key?("filename") }
    assert_equal "first.txt", @created.filename

    PaperTrail.request(whodunnit: "Replacer") do
      assert_difference -> { @created.versions.reload.count { |version| version.changeset.key?("filename") } }, 1 do
        @created.file.attach(io: StringIO.new("second"), filename: "second.txt", content_type: "text/plain")
      end
    end
    version = @created.versions.reverse.find { |candidate| candidate.changeset.key?("filename") }
    assert_equal "Replacer", version.whodunnit
    assert_equal [ "first.txt", "second.txt" ], version.changeset.fetch("filename")
  end
end
