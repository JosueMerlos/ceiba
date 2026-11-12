require "rails_helper"

RSpec.describe Appointments::Availability::Calculator do
  let(:managua) { "America/Managua" }
  let(:new_york) { "America/New_York" }

  def slot(weekday, from, to) = { weekday:, starts_minute: from * 60, ends_minute: to * 60 }

  def interval(from, to) = Appointments::Availability::Interval.new(starts_at: from, ends_at: to)

  # Managua wall-clock (UTC-6, no DST) as a UTC instant. Monday is 2026-01-05.
  def managua_time(hour, minute = 0, day: 5) = Time.utc(2026, 1, day) + (((hour + 6) * 60) + minute) * 60

  def calculate(overrides = {})
    described_class.call(
      **{ branch_slots: [ slot(1, 9, 13) ], professional_slots: [ slot(1, 9, 13) ], time_offs: [], busy: [], time_zone: managua,
          from_date: Date.new(2026, 1, 5), to_date: Date.new(2026, 1, 5), duration_minutes: 30, step_minutes: 15,
          now: Time.utc(2026, 1, 1), min_lead_minutes: 0, max_advance_days: 60 }.merge(overrides)
    )
  end

  def managua_labels(slots) = slots.map { |s| s.starts_at.in_time_zone(managua).strftime("%d %H:%M") }

  it "profesional 9-13 con una cita 10:00-10:30: huecos de 30 con paso 15 que no la solapan" do
    busy = [ interval(managua_time(10), managua_time(10, 30)) ]

    slots = calculate(busy:)

    expect(managua_labels(slots)).to eq(
      [ "05 09:00", "05 09:15", "05 09:30", "05 10:30", "05 10:45", "05 11:00", "05 11:15", "05 11:30", "05 11:45", "05 12:00", "05 12:15", "05 12:30" ]
    )
  end

  it "una ausencia de todo el día deja vacío ese día y el siguiente conserva sus huecos", :aggregate_failures do
    schedule = [ slot(1, 9, 13), slot(2, 9, 13) ]
    day_off = [ interval(managua_time(0), managua_time(0, day: 6)) ]

    slots = calculate(branch_slots: schedule, professional_slots: schedule, time_offs: day_off, to_date: Date.new(2026, 1, 6))

    expect(managua_labels(slots).map { |label| label[0, 2] }.uniq).to eq(%w[06])
    expect(managua_labels(slots).first).to eq("06 09:00")
  end

  it "ausencias solapadas restan su unión" do
    offs = [ interval(managua_time(10), managua_time(11, 30)), interval(managua_time(11), managua_time(12)) ]

    slots = calculate(time_offs: offs, step_minutes: 30)

    expect(managua_labels(slots)).to eq([ "05 09:00", "05 09:30", "05 12:00", "05 12:30" ])
  end

  it "la ventana es la intersección de sucursal y profesional (sucursal 8-18, profesional 9-13)" do
    slots = calculate(branch_slots: [ slot(1, 8, 18) ], duration_minutes: 60, step_minutes: 60)

    expect(managua_labels(slots)).to eq([ "05 09:00", "05 10:00", "05 11:00", "05 12:00" ])
  end

  it "con la intersección más estrecha del lado de la sucursal (sucursal 10-11, profesional 9-13)" do
    slots = calculate(branch_slots: [ slot(1, 10, 11) ], duration_minutes: 60, step_minutes: 60)

    expect(managua_labels(slots)).to eq([ "05 10:00" ])
  end

  it "una sucursal sin horario está cerrada: no hay huecos aunque el profesional tenga horario" do
    expect(calculate(branch_slots: [])).to be_empty
  end

  it "un profesional sin horario en la sucursal no tiene huecos" do
    expect(calculate(professional_slots: [])).to be_empty
  end

  it "aplica la anticipación mínima sobre el resultado (now 10:00, 120 min)" do
    slots = calculate(now: managua_time(10), min_lead_minutes: 120)

    expect(managua_labels(slots).first).to eq("05 12:00")
  end

  it "domingo del cambio de horario en America/New_York con 9-17: todos los huecos caen entre 9 y 17 locales", :aggregate_failures do
    schedule = [ slot(0, 9, 17) ]

    slots = calculate(branch_slots: schedule, professional_slots: schedule, time_zone: new_york, from_date: Date.new(2026, 3, 8),
                      to_date: Date.new(2026, 3, 8), step_minutes: 30, now: Time.utc(2026, 3, 1))

    expect(slots.size).to eq(16)
    expect(slots.first.starts_at).to eq(Time.utc(2026, 3, 8, 13))
    expect(slots.last.ends_at).to eq(Time.utc(2026, 3, 8, 21))
    expect(slots.map { |s| s.starts_at.in_time_zone(new_york).strftime("%H:%M") }.first(2)).to eq(%w[09:00 09:30])
    expect(slots.map { |s| s.ends_at.in_time_zone(new_york).strftime("%H:%M") }.last).to eq("17:00")
  end
end
