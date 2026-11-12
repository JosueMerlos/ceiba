require "rails_helper"

# Property test of the whole core. The oracle is deliberately independent of WeeklyExpander and SlotFinder: it builds the
# open windows with TZInfo directly and checks everything on absolute (chronological) instants.
RSpec.describe "Appointments::Availability (invariantes del núcleo)" do
  let(:scenario_count) { 600 }
  let(:seed) { Integer(ENV.fetch("AVAILABILITY_SEED") { Random.new_seed % 1_000_000 }) }
  let(:rng) { Random.new(seed) }

  # Zone and date anchors around DST changes. Mexico City stopped observing DST in 2023, so its dates are from 2022.
  def anchors
    [
      [ "America/Managua", Date.new(2026, 1, 5) ], [ "America/Managua", Date.new(2026, 7, 19) ],
      [ "America/New_York", Date.new(2026, 3, 8) ], [ "America/New_York", Date.new(2026, 11, 1) ],
      [ "America/Mexico_City", Date.new(2022, 4, 3) ], [ "America/Mexico_City", Date.new(2022, 10, 30) ]
    ]
  end

  # Branch hours are wide so that the professional's (narrower, often around the DST hours) usually intersect them.
  def random_slots(rng, dates, wide:)
    Array.new(rng.rand(1..3)) do
      starts = wide ? rng.rand(0..120) * 5 : random_start(rng)
      length = wide ? rng.rand(60..180) * 5 : rng.rand(6..120) * 5
      { weekday: dates.sample(random: rng).wday, starts_minute: starts, ends_minute: [ starts + length, 1439 ].min }
    end
  end

  def random_start(rng) = rng.rand(10) < 5 ? rng.rand(12..22) * 5 : rng.rand(0..220) * 5

  def random_spans(rng, range_start, range_end)
    Array.new(rng.rand(0..4)) do
      from = range_start + (rng.rand(0..((range_end - range_start) / 300)) * 300)
      Appointments::Availability::Interval.new(starts_at: Time.at(from).utc, ends_at: Time.at(from + (rng.rand(1..120) * 300)).utc)
    end
  end

  def random_scenario(rng)
    zone, anchor = anchors.sample(random: rng)
    tz = TZInfo::Timezone.get(zone)
    from_date = anchor - rng.rand(0..3)
    to_date = from_date + rng.rand(0..4)
    dates = (from_date..to_date).to_a
    range_start = ref_utc(tz, from_date, 0)
    range_end = ref_utc(tz, to_date + 1, 0)
    {
      time_zone: zone, from_date:, to_date:, branch_slots: random_slots(rng, dates, wide: true), professional_slots: random_slots(rng, dates, wide: false),
      time_offs: random_spans(rng, range_start, range_end), busy: random_spans(rng, range_start, range_end),
      duration_minutes: [ 5, 15, 30, 45, 60, 90 ].sample(random: rng), step_minutes: [ 5, 7, 10, 15, 20, 25, 30, 40, 45, 50 ].sample(random: rng),
      now: Time.at(range_start - (rng.rand(0..4320) * 60)).utc, min_lead_minutes: rng.rand(0..360), max_advance_days: rng.rand(1..8)
    }
  end

  # Local wall time to a UTC epoch with TZInfo only: first occurrence when ambiguous; a nonexistent time clamps to the
  # transition that created the gap.
  def ref_utc(tz, date, minute)
    local = Time.utc(date.year, date.month, date.day) + (minute * 60)
    (local - tz.period_for_local(local, true).utc_total_offset).to_i
  rescue TZInfo::PeriodNotFound
    guess = local - tz.period_for_local(local - 86_400, true).utc_total_offset
    tz.period_for_utc(guess).start_transition.at.to_time.to_i
  end

  def ref_windows(tz, slots, from_date, to_date)
    spans = (from_date..to_date).flat_map do |date|
      slots.select { |slot| slot[:weekday] == date.wday }.map { |slot| [ ref_utc(tz, date, slot[:starts_minute]), ref_utc(tz, date, slot[:ends_minute]) ] }
    end
    spans.select { |from, to| from < to }.sort.each_with_object([]) do |(from, to), merged|
      merged.last && from <= merged.last[1] ? merged.last[1] = [ merged.last[1], to ].max : merged << [ from, to ]
    end
  end

  def inside?(windows, from, to) = windows.any? { |w_from, w_to| w_from <= from && to <= w_to }

  def clash?(spans, from, to) = spans.any? { |span| span.starts_at.to_i < to && from < span.ends_at.to_i }

  def grid?(tz, epoch, step)
    local = tz.utc_to_local(Time.at(epoch).utc)
    ((local.hour * 60) + local.min) % step == 0
  end

  def calculate(scenario) = Appointments::Availability::Calculator.call(**scenario)

  def each_scenario
    scenario_count.times do |index|
      scenario = random_scenario(rng)
      yield scenario, "seed=#{seed} scenario=#{index} #{scenario.inspect}"
    end
  end

  # First broken invariant of a slot, or nil.
  def violation(slot, scenario, tz, windows)
    from = slot.starts_at.to_i
    to = slot.ends_at.to_i
    return "wrong duration" unless to - from == scenario[:duration_minutes] * 60
    return "overlaps a busy appointment" if clash?(scenario[:busy], from, to)
    return "overlaps a time off" if clash?(scenario[:time_offs], from, to)
    return "outside branch hours" unless inside?(windows[:branch], from, to)
    return "outside professional hours" unless inside?(windows[:professional], from, to)
    return "breaks min lead" if from < scenario[:now].to_i + (scenario[:min_lead_minutes] * 60)
    return "breaks max advance" if from > scenario[:now].to_i + (scenario[:max_advance_days] * 86_400)

    "off the wall-clock grid" unless grid?(tz, from, scenario[:step_minutes])
  end

  def reference_windows(scenario, tz)
    { branch: ref_windows(tz, scenario[:branch_slots], scenario[:from_date], scenario[:to_date]),
      professional: ref_windows(tz, scenario[:professional_slots], scenario[:from_date], scenario[:to_date]) }
  end

  it "ningún hueco viola los invariantes en cientos de escenarios aleatorios (con DST)", :aggregate_failures do
    with_slots = 0
    each_scenario do |scenario, label|
      tz = TZInfo::Timezone.get(scenario[:time_zone])
      windows = reference_windows(scenario, tz)
      slots = calculate(scenario)
      with_slots += 1 if slots.any?

      expect(slots.map(&:starts_at)).to eq(slots.map(&:starts_at).uniq.sort), label
      slots.each { |slot| expect(violation(slot, scenario, tz, windows)).to be_nil, "#{slot} #{label}" }
    end

    expect(with_slots).to be >= 60, "scenarios were too empty to mean anything (seed=#{seed})"
  end

  it "no omite ningún hueco válido (comprobación por fuerza bruta minuto a minuto)", :aggregate_failures do
    each_scenario do |scenario, label|
      tz = TZInfo::Timezone.get(scenario[:time_zone])
      branch = ref_windows(tz, scenario[:branch_slots], scenario[:from_date], scenario[:to_date])
      professional = ref_windows(tz, scenario[:professional_slots], scenario[:from_date], scenario[:to_date])
      duration = scenario[:duration_minutes] * 60
      lowest = scenario[:now].to_i + (scenario[:min_lead_minutes] * 60)
      highest = scenario[:now].to_i + (scenario[:max_advance_days] * 86_400)

      expected = branch.flat_map { |from, to| (from...to).step(60).to_a }.select do |start|
        start.between?(lowest, highest) && inside?(branch, start, start + duration) && inside?(professional, start, start + duration) &&
          !clash?(scenario[:busy], start, start + duration) && !clash?(scenario[:time_offs], start, start + duration) &&
          grid?(tz, start, scenario[:step_minutes])
      end

      expect(calculate(scenario).map { |slot| slot.starts_at.to_i }).to eq(expected), label
    end
  end
end
