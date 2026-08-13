ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Two versions written inside the same clock tick are indistinguishable to
# PT-AT, which indexes association membership per version but resolves it by
# timestamp. A comparison across such a pair silently reports no association
# change at all. The demo seeds a whole history in milliseconds, so tests hit
# that race a few percent of the time; keeping version timestamps strictly
# increasing removes it without changing what is being tested.
module VersionClock
  class << self
    def reset! = @last = nil

    def next(timestamp)
      current = timestamp || Time.now.utc
      current = @last + Rational(1, 1_000_000) if @last && current <= @last
      @last = current
    end
  end
end

PaperTrail::Version.before_create do
  self.created_at = VersionClock.next(created_at)
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup { VersionClock.reset! }

    # Add more helper methods to be used by all tests here...
  end
end
