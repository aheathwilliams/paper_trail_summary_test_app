class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def record_as_actor
    actor = params[:actor].to_s.strip.presence || "Manual tester"
    PaperTrail.request(whodunnit: actor.first(80)) { yield }
  end

  # The gem's checkpoint recipe. A freshly loaded root records its current
  # HABTM membership; the instance that changed the membership would record
  # it as it was before the change, and keeps doing so on every later save.
  def checkpoint!(article)
    Article.transaction { Article.find(article.id).paper_trail.save_with_version }
  end

  # PT-AT records HABTM membership only at root versions, and the gem credits
  # a change made between two of them to the step after the earlier one. A
  # checkpoint just before the change, as well as after it, makes that step
  # the actor's own.
  def with_habtm_checkpoints(article)
    checkpoint!(article)
    yield
    checkpoint!(article)
  end

  def redirect_to_article(article, **options)
    redirect_to root_path(article_id: article.id), **options
  end
end
