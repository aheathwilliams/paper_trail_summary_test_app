class Comment < ApplicationRecord
  belongs_to :article
  has_many :replies, dependent: :destroy

  has_paper_trail

  validates :author, :body, presence: true
end
