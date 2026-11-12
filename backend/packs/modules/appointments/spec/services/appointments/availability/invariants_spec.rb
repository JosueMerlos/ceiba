require "rails_helper"

# Property test of the whole core. The oracle is deliberately independent of WeeklyExpander and SlotFinder: it builds the
# open windows with TZInfo directly (every candidate instant of a local time is computed and the earliest one wins; a
# nonexistent time is located through the zone's transition list) and checks everything on absolute (chronological) instants,
# with exact fractions of a second. It also re-derives WHO gets each start (the least busy free professional, the lowest-id free
# resource of the required kind) and that the whole block, buffers included, fits the assigned professional's and resource's time.
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
      Appointments::Availability::WeeklySlot.new(weekday: dates.sample(random: rng).wday, starts_minute: starts, ends_minute: [ starts + length, 1439 ].min)
    end
  end

  def random_start(rng) = rng.rand(10) < 5 ? rng.rand(12..22) * 5 : rng.rand(0..220) * 5

  # Whole 5-minute spans, and in a third of them a fraction of a second on either edge (exact Rationals, no float noise).
  def random_spans(rng, range_start, range_end)
    Array.new(rng.rand(0..4)) do
      from = range_start + (rng.rand(0..((range_end - range_start) / 300)) * 300) + fraction(rng)
      Appointments::Availability::Interval.new(starts_at: Time.at(from).utc, ends_at: Time.at(from + (rng.rand(1..120) * 300) + fraction(rng)).utc)
    end
  end

  def fraction(rng) = rng.rand(3).zero? ? Rational(rng.rand(1..999), 1000) : 0

  def random_people(rng, dates, range_start, range_end)
    ids = %w[a b c d].sample(rng.rand(2..4), random: rng)
    ids.map do |id|
      { id:, slots: random_slots(rng, dates, wide: false), time_offs: random_spans(rng, range_start, range_end), busy: random_spans(rng, range_start, range_end) }
    end
  end

  # A third of the resources have no hours of their own (they follow the branch's).
  def random_resources(rng, dates, range_start, range_end)
    ids = %w[r1 r2 r3].sample(rng.rand(0..3), random: rng)
    ids.map do |id|
      { id:, kind: %w[room chair].sample(random: rng), slots: rng.rand(3).zero? ? [] : random_slots(rng, dates, wide: false),
        time_offs: random_spans(rng, range_start, range_end), busy: random_spans(rng, range_start, range_end) }
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
    professionals = random_people(rng, dates, range_start, range_end)
    required = rng.rand(2).zero? ? nil : %w[room chair].sample(random: rng)
    {
      time_zone: zone, from_date:, to_date:, branch_slots: random_slots(rng, dates, wide: true), professionals:,
      resources: random_resources(rng, dates, range_start, range_end),
      plan: Appointments::Availability::ServicePlan.new(duration_minutes: [ 5, 15, 30, 45, 60, 90 ].sample(random: rng), buffer_before_minutes: [ 0, 0, 5, 10, 15 ].sample(random: rng),
                                                        buffer_after_minutes: [ 0, 0, 5, 10, 15 ].sample(random: rng), price_minor: 0, currency: "NIO", required_kind: required),
      load_by_day: professionals.to_h { |person| [ person[:id], (from_date..(to_date + 1)).to_h { |date| [ date, rng.rand(0..3) ] } ] },
      step_minutes: [ 5, 7, 10, 15, 20, 25, 30, 40, 45, 50 ].sample(random: rng),
      now: Time.at(range_start - (rng.rand(-1440..4320) * 60) + fraction(rng)).utc, min_lead_minutes: [ 0, 0, rng.rand(0..360) ].sample(random: rng), max_advance_days: rng.rand(1..8)
    }
  end

  # Local wall time to a UTC epoch with TZInfo only. Every period that holds the local time gives a candidate instant and the
  # earliest wins (the first occurrence of a repeated hour). A nonexistent time clamps to the transition whose gap holds it.
  def ref_utc(tz, date, minute)
    local = Time.utc(date.year, date.month, date.day) + (minute * 60)
    candidates = tz.periods_for_local(local).map { |period| (local - period.utc_total_offset).to_i }
    return candidates.min if candidates.any?

    tz.transitions_up_to(local + 86_400, local - 86_400).find { |transition| in_gap?(transition, local) }.at.to_time.to_i
  end

  def in_gap?(transition, local)
    wall_before = transition.at.to_time.to_i + transition.previous_offset.utc_total_offset
    wall_after = transition.at.to_time.to_i + transition.offset.utc_total_offset
    local.to_i >= wall_before && local.to_i < wall_after
  end

  def ref_windows(tz, slots, from_date, to_date)
    spans = (from_date..to_date).flat_map do |date|
      slots.select { |slot| slot.weekday == date.wday }.map { |slot| [ ref_utc(tz, date, slot.starts_minute), ref_utc(tz, date, slot.ends_minute) ] }
    end
    spans.select { |from, to| from < to }.sort.each_with_object([]) do |(from, to), merged|
      merged.last && from <= merged.last[1] ? merged.last[1] = [ merged.last[1], to ].max : merged << [ from, to ]
    end
  end

  def inside?(windows, from, to) = windows.any? { |w_from, w_to| w_from <= from && to <= w_to }

  def clash?(spans, from, to) = spans.any? { |span| span.starts_at.to_r < to && from < span.ends_at.to_r }

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

  def local_date(tz, epoch) = tz.utc_to_local(Time.at(epoch).utc).to_date

  def reference_windows(scenario, tz)
    range = scenario.values_at(:from_date, :to_date)
    { branch: ref_windows(tz, scenario[:branch_slots], *range),
      owners: (scenario[:professionals] + scenario[:resources]).to_h { |owner| [ owner[:id], ref_windows(tz, owner[:slots], *range) ] } }
  end

  # The block [from, to) fits the open hours (the owner's own, or the branch's alone for a resource without any) and touches no
  # absence or appointment of the owner.
  def owner_free?(owner, windows, from, to)
    own_hours = owner[:slots].empty? ? windows[:branch] : windows[:owners].fetch(owner[:id])
    inside?(windows[:branch], from, to) && inside?(own_hours, from, to) && !clash?(owner[:time_offs], from, to) && !clash?(owner[:busy], from, to)
  end

  def block_of(scenario, start)
    plan = scenario[:plan]
    [ start - (plan.buffer_before_minutes * 60), start + ((plan.duration_minutes + plan.buffer_after_minutes) * 60) ]
  end

  def candidate_resources(scenario) = scenario[:resources].select { it[:kind] == scenario[:plan].required_kind }

  # First broken invariant of a slot, or nil.
  def violation(slot, scenario, tz, windows)
    from = slot.starts_at.to_i
    to = slot.ends_at.to_i
    return "wrong duration" unless to - from == scenario[:plan].duration_minutes * 60
    return "breaks min lead" if from < scenario[:now].to_r + (scenario[:min_lead_minutes] * 60)
    return "block starts in the past" if block_of(scenario, from).first < scenario[:now].to_r
    return "breaks max advance" if from > scenario[:now].to_r + (scenario[:max_advance_days] * 86_400)
    return "off the wall-clock grid" unless grid?(tz, from, scenario[:step_minutes])

    resource_violation(slot, scenario, windows, *block_of(scenario, from)) || professional_violation(slot, scenario, windows, *block_of(scenario, from))
  end

  def professional_violation(slot, scenario, windows, from, to)
    person = scenario[:professionals].find { it[:id] == slot.professional_id }
    return "unknown professional" unless person
    return "block overlaps a busy appointment" if clash?(person[:busy], from, to)
    return "block overlaps a time off" if clash?(person[:time_offs], from, to)

    "block outside the professional's hours or the branch's" unless inside?(windows[:branch], from, to) && inside?(windows[:owners].fetch(person[:id]), from, to)
  end

  def resource_violation(slot, scenario, windows, from, to)
    return slot.resource_id.nil? ? nil : "resource assigned without being required" if scenario[:plan].required_kind.nil?

    resource = candidate_resources(scenario).find { it[:id] == slot.resource_id }
    return "no compatible resource assigned" unless resource

    "block does not fit the resource's free time" unless owner_free?(resource, windows, from, to)
  end

  # What the engine must offer, by brute force: every whole minute of the branch hours on the grid, kept when some professional
  # (and some resource, if a kind is required) is free for the whole block. Assignment: the least busy free professional on that
  # local day (ties by id) and the lowest-id free resource. Rows of [epoch, professional_id, resource_id].
  def expected_slots(scenario, tz, windows)
    lowest = scenario[:now].to_r + (scenario[:min_lead_minutes] * 60)
    highest = scenario[:now].to_r + (scenario[:max_advance_days] * 86_400)
    starts = windows[:branch].flat_map { |from, to| (from...to).step(60).to_a }.select { it.between?(lowest, highest) && block_of(scenario, it).first >= scenario[:now].to_r && grid?(tz, it, scenario[:step_minutes]) }

    starts.filter_map do |start|
      block = block_of(scenario, start)
      free = scenario[:professionals].select { owner_free?(it, windows, *block) }
      resources = candidate_resources(scenario).select { owner_free?(it, windows, *block) }
      next if free.empty? || (scenario[:plan].required_kind && resources.empty?)

      day = local_date(tz, start)
      chosen = free.min_by { [ scenario[:load_by_day].dig(it[:id], day) || 0, it[:id] ] }
      [ start, chosen[:id], scenario[:plan].required_kind ? resources.map { it[:id] }.min : nil ]
    end
  end

  it "ningún hueco viola los invariantes en cientos de escenarios aleatorios (con DST)", :aggregate_failures do
    with_slots = 0
    with_resource = 0
    each_scenario do |scenario, label|
      tz = TZInfo::Timezone.get(scenario[:time_zone])
      windows = reference_windows(scenario, tz)
      slots = calculate(scenario)
      with_slots += 1 if slots.any?
      with_resource += 1 if slots.any?(&:resource_id)

      expect(slots.map(&:starts_at)).to eq(slots.map(&:starts_at).uniq.sort), label
      slots.each { |slot| expect(violation(slot, scenario, tz, windows)).to be_nil, "#{slot} #{label}" }
    end

    expect(with_slots).to be >= 60, "scenarios were too empty to mean anything (seed=#{seed})"
    expect(with_resource).to be >= 20, "too few scenarios exercised a resource (seed=#{seed})"
  end

  it "no omite ningún hueco válido y asigna profesional y recurso según la política (fuerza bruta por inicio)", :aggregate_failures do
    each_scenario do |scenario, label|
      tz = TZInfo::Timezone.get(scenario[:time_zone])
      expected = expected_slots(scenario, tz, reference_windows(scenario, tz))

      actual = calculate(scenario).map { [ it.starts_at.to_i, it.professional_id, it.resource_id ] }

      expect(actual).to eq(expected), label
    end
  end
end
