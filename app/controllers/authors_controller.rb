class AuthorsController < ApplicationController
  def create
    author = Author.new(author_params)
    article = Article.find_by(id: params[:article_id])

    record_as_actor do
      author.save!
      if article
        article.authorships.create!(author: author)
        checkpoint!(article)
      end
    end

    redirect_after_author_change(article, notice: "Author created#{' and attached' if article}.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_after_author_change(article, alert: error.record.errors.full_messages.to_sentence)
  end

  def update
    author = Author.find(params[:id])
    articles = author.articles.to_a

    record_as_actor do
      author.update!(author_params)
      articles.each { |article| checkpoint!(article) }
    end

    redirect_after_author_change(selected_article(articles), notice: "Author updated across every linked article checkpoint.")
  rescue ActiveRecord::RecordInvalid => error
    redirect_after_author_change(selected_article(articles), alert: error.record.errors.full_messages.to_sentence)
  end

  private

  def author_params
    params.expect(author: %i[name bio])
  end

  def selected_article(articles)
    requested = articles.find { |article| article.id.to_s == params[:article_id].to_s }
    requested || articles.first
  end

  def redirect_after_author_change(article, **options)
    if article
      redirect_to_article(article, **options)
    else
      redirect_to root_path, **options
    end
  end
end
