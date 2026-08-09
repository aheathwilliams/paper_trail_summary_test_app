class Tag < ApplicationRecord
  has_and_belongs_to_many :articles

  has_paper_trail

  validates :name, :description, presence: true
  validates :name, uniqueness: true
end
