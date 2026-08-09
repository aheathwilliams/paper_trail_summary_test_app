class ArticlesController < ApplicationController
  def create
    article = Article.new(article_params)
    record_as_actor do
      article.save!
      checkpoint!(article)
    end

    redirect_to_article(article, notice: "Article created with its first comparison checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.record.errors.full_messages.to_sentence
  end

  def update
    article = Article.find(params[:id])
    record_as_actor do
      article.update!(article_params)
      checkpoint!(article)
    end

    redirect_to_article(article, notice: "Article updated and checkpointed.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(error.record, alert: error.record.errors.full_messages.to_sentence)
  end

  private

  def article_params
    params.expect(article: %i[title status body])
  end
end
