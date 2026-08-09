class TaggingsController < ApplicationController
  before_action :set_article

  def create
    tag = Tag.find(tagging_params.fetch(:tag_id))
    record_as_actor do
      @article.tags << tag
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Tag attached and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def destroy
    tag = @article.tags.find(params[:id])
    record_as_actor do
      @article.tags.delete(tag)
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Tag detached and captured in a new article checkpoint.")
  end

  private

  def set_article
    @article = Article.find(params[:article_id])
  end

  def tagging_params
    params.expect(tagging: [ :tag_id ])
  end
end
