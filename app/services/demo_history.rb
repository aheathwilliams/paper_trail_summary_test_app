class DemoHistory
  class << self
    def create!
      clear!

      article = as("Maya Chen") do
        Article.create!(
          title: "Apollo Notes",
          status: "draft",
          body: "A short opening about the Apollo program."
        )
      end

      lead_author = as("Maya Chen") do
        Author.create!(
          name: "Maya Chen",
          bio: "Science journalist and Apollo enthusiast."
        )
      end
      as("Maya Chen") do
        Authorship.create!(
          article: article,
          author: lead_author,
          role: "lead",
          position: 1,
          credited_as: "Maya Chen"
        )
      end

      opening_comment = as("Jon Bell") do
        article.comments.create!(
          author: "Jon Bell",
          body: "The opening needs a clearer sense of place."
        )
      end
      opening_reply = as("Maya Chen") do
        opening_comment.replies.create!(
          responder: "Maya Chen",
          body: "I will add the launch-site context."
        )
      end
      removed_reply = as("Jon Bell") do
        opening_comment.replies.create!(
          responder: "Jon Bell",
          body: "Also define the mission acronym."
        )
      end
      apollo_tag = as("Maya Chen") do
        Tag.create!(
          name: "Apollo",
          description: "Draft coverage of the Apollo program."
        )
      end
      removed_tag = as("Jon Bell") do
        Tag.create!(
          name: "Needs sources",
          description: "Claims still awaiting citations."
        )
      end
      as("Maya Chen") { article.tags << [ apollo_tag, removed_tag ] }
      article.reload
      as("Maya Chen") { association_checkpoint!(article) }

      as("Maya Chen") do
        article.update!(
          title: "Apollo Notes — First Revision",
          status: "review"
        )
      end

      as("Jon Bell") do
        opening_comment.update!(body: "The new opening works well.")
      end
      as("Maya Chen") do
        opening_reply.update!(body: "The launch-site context is now in the lead.")
      end
      as("Jon Bell") { removed_reply.destroy! }
      as("Luis Ortega") do
        opening_comment.replies.create!(
          responder: "Luis Ortega",
          body: "The mission acronym is defined in the second paragraph."
        )
      end
      as("Maya Chen") do
        lead_author.update!(bio: "Senior science journalist and Apollo historian.")
      end
      second_author = as("Luis Ortega") do
        Author.create!(
          name: "Luis Ortega",
          bio: "Research editor focused on aerospace history."
        )
      end
      as("Luis Ortega") do
        Authorship.create!(
          article: article,
          author: second_author,
          role: "contributor",
          position: 2,
          credited_as: "Luis Ortega"
        )
      end
      sources_comment = as("Priya Shah") do
        article.comments.create!(
          author: "Priya Shah",
          body: "Add a source for the launch-date claim."
        )
      end
      as("Maya Chen") do
        apollo_tag.update!(description: "Reporting on Apollo history and its cultural legacy.")
        article.tags.delete(removed_tag)
      end
      verified_tag = as("Priya Shah") do
        Tag.create!(
          name: "Verified",
          description: "Major factual claims have supporting sources."
        )
      end
      as("Priya Shah") { article.tags << verified_tag }
      article.reload

      as("Maya Chen") do
        article.update!(
          status: "fact_check",
          body: "An expanded account of Apollo, its launch, and its cultural impact."
        )
      end

      as("Priya Shah") { sources_comment.destroy! }
      as("Maya Chen") { article.authorships.find_by!(author: lead_author).destroy! }
      fact_checker = as("Priya Shah") do
        Author.create!(
          name: "Priya Shah",
          bio: "Fact checker and archival researcher."
        )
      end
      as("Priya Shah") { Authorship.create!(article: article, author: fact_checker) }
      as("Luis Ortega") do
        article.comments.create!(
          author: "Luis Ortega",
          body: "Sources checked. This is ready to publish."
        )
      end

      as("Maya Chen") do
        article.update!(
          title: "Apollo Notes — Final",
          status: "approved"
        )
      end

      as("Luis Ortega") do
        article.authorships.find_by!(author: second_author).update!(
          role: "co-lead",
          position: 1,
          credited_as: "L. Ortega"
        )
      end

      # Three people edit the root in a row, which is what makes a per-person
      # report worth filtering. Each transition is bounded by the version that
      # immediately followed it, because a version stores the state before its
      # own event, so that next version is the only record of what the edit
      # produced. Bounding by the same person's *next* edit instead would credit
      # them with everything the others did in between.
      as("Priya Shah") do
        article.update!(body: "An account of Apollo, held for a final copy pass.")
      end
      as("Jon Bell") do
        article.update!(body: "An account of Apollo, with its sources checked.")
      end

      as("Maya Chen") do
        article.update!(
          body: "A polished account of Apollo, its launch, and its lasting cultural impact."
        )
        article.touch
      end
      as("Maya Chen") { association_checkpoint!(article) }

      article.reload
    end

    private

    def as(person, &block)
      PaperTrail.request(whodunnit: person, &block)
    end

    def association_checkpoint!(article)
      fresh_article = Article.find(article.id)
      Article.transaction { fresh_article.paper_trail.save_with_version }
    end

    def clear!
      PaperTrail::VersionAssociation.delete_all
      PaperTrail::Version.delete_all
      ApplicationRecord.connection.delete("DELETE FROM articles_tags")
      Reply.delete_all
      Comment.delete_all
      Authorship.delete_all
      Author.delete_all
      Tag.delete_all
      Article.delete_all
    end
  end
end
