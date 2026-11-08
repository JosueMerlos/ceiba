# Mide cuántos segundos tarda el bloque (reloj monótono).
module Timing
  def elapsed_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end

RSpec.configure { |config| config.include Timing }
