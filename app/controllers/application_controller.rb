class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def record_as_actor
    actor = params[:actor].to_s.strip.presence || "Manual tester"
    PaperTrail.request(whodunnit: actor.first(80)) { yield }
  end

  def checkpoint!(article)
    # A fresh root instance snapshots current HABTM membership instead of the
    # caller's PT-AT change buffer, which represents membership before mutation.
    Article.find(article.id).touch
  end

  def redirect_to_article(article, **options)
    redirect_to root_path(article_id: article.id), **options
  end
end
