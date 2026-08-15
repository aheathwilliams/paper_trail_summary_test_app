class Article < ApplicationRecord
  STATUSES = %w[draft review fact_check approved archived].freeze

  # demo:code shared.model
  has_many :comments, dependent: :destroy
  has_many :authorships, dependent: :destroy
  has_many :authors, through: :authorships
  has_and_belongs_to_many :tags
  # An attachment audited through a model this application owns; see
  # DocumentRevision for why it cannot go through ActiveStorage directly.
  has_many :document_revisions, as: :attachable, dependent: :destroy

  # Every model whose history is compared needs this, including the children
  # and the join model -- not just the root.
  has_paper_trail synchronize_version_creation_timestamp: false
  # demo:code end

  validates :title, :status, :body, presence: true
  validates :status, inclusion: { in: STATUSES }
end
