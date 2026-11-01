# Keeps PaperTrail version timestamps strictly increasing while it is on.
#
# WSL2's clock sometimes steps backwards. A version stamped earlier than the
# one written just before it changes the order the gem reads the history in,
# so a seeded demo would show changes in the wrong steps or lose them: one
# half-second step during seeding broke the seed's endpoint counts at most of
# the points it was tried. The demo seeds and the test suite turn it on;
# ordinary requests keep PaperTrail's own timestamps.
#
# Versions that only share a timestamp need no help: the gem orders them by
# id. test/models/version_order_test.rb writes such a tie on purpose.
module VersionClock
  class << self
    def on? = @always || Thread.current[:version_clock]
    def always! = @always = true
    def reset! = @last = nil

    def monotonic
      previous = Thread.current[:version_clock]
      Thread.current[:version_clock] = true
      yield
    ensure
      Thread.current[:version_clock] = previous
    end

    def next(timestamp)
      current = timestamp || Time.now.utc
      current = @last + Rational(1, 1_000_000) if @last && current <= @last
      @last = current
    end
  end
end
