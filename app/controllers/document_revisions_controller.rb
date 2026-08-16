# Attaching a file writes to ActiveStorage's tables and nothing to a versioned
# record, so every action here goes through DocumentRevision, which mirrors the
# blob's metadata onto columns PaperTrail records. See that model for why the
# attachment cannot be audited directly.
class DocumentRevisionsController < ApplicationController
  before_action :set_article

  def create
    record_as_actor do
      revision = @article.document_revisions.create!(label: revision_params.fetch(:label))
      revision.file.attach(revision_params.fetch(:file))
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Document attached and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  # Replacing the file is the case worth watching: the metadata moves, and the
  # change lands on a versioned record rather than only in ActiveStorage.
  def update
    revision = @article.document_revisions.find(params[:id])
    record_as_actor do
      revision.file.attach(revision_params.fetch(:file))
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Document replaced; the filename and checksum changed.")
  end

  def destroy
    revision = @article.document_revisions.find(params[:id])
    record_as_actor do
      revision.destroy!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Document removed and captured in a new article checkpoint.")
  end

  private

  def set_article
    @article = Article.find(params[:article_id])
  end

  def revision_params
    params.expect(document_revision: [ :label, :file ])
  end
end
