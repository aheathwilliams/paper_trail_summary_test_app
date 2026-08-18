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
    attributes = params.expect(article: %i[title status body metadata])
    return attributes unless attributes.key?(:metadata)

    attributes.merge(metadata: parsed_metadata(attributes[:metadata]))
  end

  # The form edits the JSON column as text, so what arrives is a string. A
  # blank field clears the column; anything unparseable is the caller's typo
  # rather than a state worth storing.
  def parsed_metadata(raw)
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    raise ActiveRecord::RecordInvalid, invalid_metadata unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    raise ActiveRecord::RecordInvalid, invalid_metadata
  end

  def invalid_metadata
    Article.new.tap { |article| article.errors.add(:metadata, "must be a JSON object") }
  end
end
