class Reply < ApplicationRecord
  belongs_to :comment

  has_paper_trail

  validates :responder, :body, presence: true
end
