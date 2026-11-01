ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# A host clock that steps backwards, as WSL2's does, can stamp a version
# earlier than the one written before it, and the tests seed whole histories
# in milliseconds. VersionClock keeps every version timestamp in the suite
# strictly increasing; see app/services/version_clock.rb.
VersionClock.always!

module ActiveSupport
  class TestCase
    # The suite crossed the default threshold of 50 and started forking workers,
    # at which point the report tests began failing roughly one run in ten, with
    # the report finding no changed articles at all. Single-process runs are
    # clean. The seeded history is shared state -- a module-level version clock,
    # and a `clear!` that empties every table -- so workers are the wrong shape
    # for it, and at three seconds the suite gains nothing from them.
    parallelize(workers: :number_of_processors, threshold: 500)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup { VersionClock.reset! }

    # Add more helper methods to be used by all tests here...
  end
end
