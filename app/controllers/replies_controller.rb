class RepliesController < ApplicationController
  before_action :set_article_and_comment

  def create
    reply = @comment.replies.build(reply_params)
    record_as_actor do
      reply.save!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Reply created and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def update
    reply = @comment.replies.find(params[:id])
    record_as_actor do
      reply.update!(reply_params)
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Reply updated and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def destroy
    reply = @comment.replies.find(params[:id])
    record_as_actor do
      reply.destroy!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Reply removed and captured in a new article checkpoint.")
  end

  private

  def set_article_and_comment
    @article = Article.find(params[:article_id])
    @comment = @article.comments.find(params[:comment_id])
  end

  def reply_params
    params.expect(reply: %i[responder body])
  end
end
