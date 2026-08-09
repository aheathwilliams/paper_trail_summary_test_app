class Author < ApplicationRecord
  has_many :authorships, dependent: :destroy
  has_many :articles, through: :authorships

  has_paper_trail

  validates :name, :bio, presence: true
end
