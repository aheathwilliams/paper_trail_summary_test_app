class CommentsController < ApplicationController
  before_action :set_article

  def create
    comment = @article.comments.build(comment_params)
    record_as_actor do
      comment.save!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Comment created and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def update
    comment = @article.comments.find(params[:id])
    record_as_actor do
      comment.update!(comment_params)
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Comment updated and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def destroy
    comment = @article.comments.find(params[:id])
    record_as_actor do
      comment.destroy!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Comment removed and captured in a new article checkpoint.")
  end

  private

  def set_article
    @article = Article.find(params[:article_id])
  end

  def comment_params
    params.expect(comment: %i[author body])
  end
end
