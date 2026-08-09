require "test_helper"

class ReplyTest < ActiveSupport::TestCase
  test "belongs to a versioned comment" do
    reply = replies(:one)

    assert_equal comments(:one), reply.comment
    assert_respond_to reply, :versions
  end
end
