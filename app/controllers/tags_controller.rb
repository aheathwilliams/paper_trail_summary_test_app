class TagsController < ApplicationController
  def create
    tag = Tag.new(tag_params)
    article = Article.find_by(id: params[:article_id])

    record_as_actor do
      tag.save!
      if article
        article.tags << tag
        checkpoint!(article)
      end
    end

    redirect_after_tag_change(article, notice: "Tag created#{' and attached' if article}.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_after_tag_change(article, alert: error.record.errors.full_messages.to_sentence)
  end

  def update
    tag = Tag.find(params[:id])
    articles = tag.articles.to_a

    record_as_actor do
      tag.update!(tag_params)
      articles.each { |article| checkpoint!(article) }
    end

    redirect_after_tag_change(selected_article(articles), notice: "Tag updated across every linked article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_after_tag_change(selected_article(articles), alert: error.record.errors.full_messages.to_sentence)
  end

  private

  def tag_params
    params.expect(tag: %i[name description])
  end

  def selected_article(articles)
    requested = articles.find { |article| article.id.to_s == params[:article_id].to_s }
    requested || articles.first
  end

  def redirect_after_tag_change(article, **options)
    if article
      redirect_to_article(article, **options)
    else
      redirect_to root_path, **options
    end
  end
end
