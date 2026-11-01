require "test_helper"
require_relative "../support/history_oracle"

# Rebuilt history against the states the application really went through;
# see test/support/history_oracle.rb. ORACLE_SEEDS=1..50 and ORACLE_STEPS=80
# widen a run.
class HistoryOracleTest < ActiveSupport::TestCase
  def self.seeds
    first, last = ENV.fetch("ORACLE_SEEDS", "1..2").split("..").map { Integer(_1) }
    (first..(last || first)).to_a
  end

  STEPS = Integer(ENV.fetch("ORACLE_STEPS", 40))

  seeds.each do |seed|
    test "rebuilds every recorded state (seed #{seed})" do
      DemoHistory.send(:clear!)
      history = HistoryOracle::History.new(seed, STEPS).build
      checker = HistoryOracle::Checker.new(history)
      random = Random.new(seed)

      checker.endpoints(random)
      checker.activity
      checker.activity(group: :transaction)
      2.times { checker.report_window(random) }

      assert_operator checker.checks, :>, 100
      assert_empty checker.failures, lambda {
        "#{checker.failures.length} of #{checker.checks} checks failed:\n#{checker.failures.first(10).join("\n")}"
      }
    end
  end
end
