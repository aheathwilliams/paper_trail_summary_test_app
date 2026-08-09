class Article < ApplicationRecord
  STATUSES = %w[draft review fact_check approved archived].freeze

  has_many :comments, dependent: :destroy
  has_many :authorships, dependent: :destroy
  has_many :authors, through: :authorships
  has_and_belongs_to_many :tags

  has_paper_trail synchronize_version_creation_timestamp: false

  validates :title, :status, :body, presence: true
  validates :status, inclusion: { in: STATUSES }
end
