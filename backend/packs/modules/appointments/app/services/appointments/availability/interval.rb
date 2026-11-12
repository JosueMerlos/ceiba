module Appointments
  module Availability
    # Half-open [starts_at, ends_at) span of UTC instants: two spans that only touch at an edge do not overlap.
    Interval = Data.define(:starts_at, :ends_at) do
      def initialize(starts_at:, ends_at:)
        raise ArgumentError, "interval must start before it ends" unless starts_at < ends_at

        super
      end

      def overlaps?(other) = starts_at < other.ends_at && other.starts_at < ends_at

      def cover?(other) = starts_at <= other.starts_at && other.ends_at <= ends_at

      # Seconds.
      def duration = ends_at - starts_at
    end
  end
end
