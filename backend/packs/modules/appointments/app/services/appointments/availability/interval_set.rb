module Appointments
  module Availability
    # Normalized list of intervals: sorted, non-overlapping and with no adjacent pair (those are merged). Every operation
    # is a linear sweep over two sorted lists and returns a normalized set.
    class IntervalSet
      attr_reader :intervals

      def initialize(intervals = [])
        @intervals = normalize(intervals).freeze
        freeze
      end

      def empty? = intervals.empty?

      def union(other) = self.class.new(intervals + other.intervals)

      def intersect(other)
        result = []
        walk_pairs(other) do |mine, theirs|
          from = [ mine.starts_at, theirs.starts_at ].max
          to = [ mine.ends_at, theirs.ends_at ].min
          result << Interval.new(starts_at: from, ends_at: to) if from < to
        end
        self.class.new(result)
      end

      def subtract(other)
        result = []
        removals = other.intervals
        cursor = 0
        intervals.each do |interval|
          start = interval.starts_at
          cursor += 1 while cursor < removals.size && removals[cursor].ends_at <= start
          index = cursor
          while index < removals.size && removals[index].starts_at < interval.ends_at
            result << Interval.new(starts_at: start, ends_at: removals[index].starts_at) if start < removals[index].starts_at
            start = [ start, removals[index].ends_at ].max
            index += 1
          end
          result << Interval.new(starts_at: start, ends_at: interval.ends_at) if start < interval.ends_at
        end
        self.class.new(result)
      end

      # The whole interval must fit inside a single span of the set.
      def cover?(interval) = intervals.any? { |own| own.cover?(interval) }

      def ==(other) = other.is_a?(self.class) && intervals == other.intervals
      alias_method :eql?, :==

      def hash = intervals.hash

      private

      def normalize(list)
        list.sort_by(&:starts_at).each_with_object([]) do |interval, merged|
          last = merged.last
          if last && interval.starts_at <= last.ends_at
            merged[-1] = Interval.new(starts_at: last.starts_at, ends_at: [ last.ends_at, interval.ends_at ].max)
          else
            merged << interval
          end
        end
      end

      # Yields each overlapping-candidate pair once, advancing whichever list ends first.
      def walk_pairs(other)
        mine = intervals
        theirs = other.intervals
        i = j = 0
        while i < mine.size && j < theirs.size
          yield mine[i], theirs[j]
          mine[i].ends_at < theirs[j].ends_at ? i += 1 : j += 1
        end
      end
    end
  end
end
