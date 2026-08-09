class Authorship < ApplicationRecord
  belongs_to :article
  belongs_to :author

  has_paper_trail

  validates :author_id, uniqueness: { scope: :article_id }
  validates :role, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
