class AuthorshipsController < ApplicationController
  before_action :set_article

  def create
    authorship = @article.authorships.build(authorship_params)
    record_as_actor do
      authorship.save!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Author attached and captured in a new article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_to_article(@article, alert: error.record.errors.full_messages.to_sentence)
  end

  def destroy
    authorship = @article.authorships.find(params[:id])
    record_as_actor do
      authorship.destroy!
      checkpoint!(@article)
    end

    redirect_to_article(@article, notice: "Author detached and captured in a new article checkpoint.")
  end

  private

  def set_article
    @article = Article.find(params[:article_id])
  end

  def authorship_params
    params.expect(authorship: %i[author_id role position credited_as])
  end
end
