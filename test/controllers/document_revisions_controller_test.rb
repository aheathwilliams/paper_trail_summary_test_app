require "test_helper"

class DocumentRevisionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @article = DemoHistory.create!
  end

  def upload(name, body)
    Rack::Test::UploadedFile.new(StringIO.new(body), "text/plain", original_filename: name)
  end

  test "attaching a document records it on a versioned record" do
    assert_difference -> { DocumentRevision.count }, 1 do
      post article_document_revisions_url(@article), params: {
        document_revision: { label: "Contract", file: upload("contract-v1.txt", "first") },
        actor: "Casey Tester"
      }
    end

    assert_redirected_to root_url(article_id: @article.id)
    revision = DocumentRevision.order(:id).last
    assert_equal "contract-v1.txt", revision.filename
    assert_equal "Casey Tester", revision.versions.last.whodunnit
  end

  test "replacing the file moves the metadata and the gem sees it" do
    post article_document_revisions_url(@article), params: {
      document_revision: { label: "Contract", file: upload("contract-v1.txt", "first") },
      actor: "Casey Tester"
    }
    revision = DocumentRevision.order(:id).last
    @article.reload
    Article.transaction { Article.find(@article.id).paper_trail.save_with_version }
    before = @article.versions.reload.last

    patch article_document_revision_url(@article, revision), params: {
      document_revision: { file: upload("contract-v2.txt", "second, longer") },
      actor: "Dana Reviewer"
    }

    assert_redirected_to root_url(article_id: @article.id)
    @article.reload
    Article.transaction { Article.find(@article.id).paper_trail.save_with_version }
    after = @article.versions.reload.last

    diff = PaperTrailDiff.compare(before, after, associations: [ "document_revisions" ])
    changed = diff.associations["document_revisions"].changed.first
    assert_equal({ from: "contract-v1.txt", to: "contract-v2.txt" },
                 changed.attributes.fetch("filename").to_h)
    assert_equal "Dana Reviewer", revision.versions.reload.last.whodunnit
  end

  test "removing a document is recorded too" do
    post article_document_revisions_url(@article), params: {
      document_revision: { label: "Contract", file: upload("contract-v1.txt", "first") },
      actor: "Casey Tester"
    }
    revision = DocumentRevision.order(:id).last

    assert_difference -> { DocumentRevision.count }, -1 do
      delete article_document_revision_url(@article, revision), params: { actor: "Casey Tester" }
    end

    assert_redirected_to root_url(article_id: @article.id)
  end

  test "the page explains why attachments are audited indirectly" do
    get root_url

    assert_response :success
    assert_select ".documents-panel h2", text: "Documents"
    assert_select ".documents-explainer", text: /ActiveStorage/
    assert_select ".documents-explainer code", text: "UnversionedAssociationError"
    assert_select ".documents-panel input[type=file]"
    # The model that makes the pattern work is published in the code disclosure.
    assert_select ".source-snippet figcaption code", text: "app/models/document_revision.rb"
  end
end
