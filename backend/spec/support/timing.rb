# Measures how many seconds the block takes (monotonic clock).
module Timing
  def elapsed_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end

RSpec.configure { |config| config.include Timing }
