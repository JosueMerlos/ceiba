require "rails_helper"

RSpec.describe Appointments::Availability::SlotFinder do
  let(:managua) { "America/Managua" }
  let(:new_york) { "America/New_York" }
  let(:long_ago) { Time.utc(2026, 1, 1) }

  # Local Managua wall-clock (UTC-6, no DST) of 2026-01-05 as a UTC instant.
  def managua_time(hour, minute = 0, day: 5) = Time.utc(2026, 1, day) + (((hour + 6) * 60) + minute) * 60

  def interval(from, to) = Appointments::Availability::Interval.new(starts_at: from, ends_at: to)

  def free_set(*pairs) = Appointments::Availability::IntervalSet.new(pairs.map { |from, to| interval(from, to) })

  def find(free, zone: managua, duration: 30, step: 15, now: long_ago, lead: 0, max_days: 365)
    described_class.call(free:, duration_minutes: duration, step_minutes: step, time_zone: zone, now:, min_lead_minutes: lead, max_advance_days: max_days)
  end

  def starts(slots) = slots.map { |slot| slot.starts_at.utc.iso8601 }

  def managua_starts(slots) = slots.map { |slot| slot.starts_at.in_time_zone(managua).strftime("%H:%M") }

  describe "rejilla y huecos" do
    it "ofrece cada paso dentro de cada tramo libre y ninguno que cruce una cita (horario 9-13, cita 10:00-10:30)" do
      free = free_set([ managua_time(9), managua_time(10) ], [ managua_time(10, 30), managua_time(13) ])

      slots = find(free)

      expect(managua_starts(slots)).to eq(%w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30])
    end

    it "cada hueco dura exactamente la duración pedida" do
      slots = find(free_set([ managua_time(9), managua_time(13) ]), duration: 45)

      expect(slots.map(&:duration).uniq).to eq([ 2700.0 ])
    end

    it "tras una cita que termina a las 10:40 el siguiente inicio es 10:45 (rejilla del reloj local)" do
      free = free_set([ managua_time(9), managua_time(10) ], [ managua_time(10, 40), managua_time(13) ])

      expect(managua_starts(find(free)).first(5)).to eq(%w[09:00 09:15 09:30 10:45 11:00])
    end

    it "un horario que abre a las 9:10 ofrece 9:15 como primer inicio" do
      expect(managua_starts(find(free_set([ managua_time(9, 10), managua_time(10) ]))).first).to eq("09:15")
    end

    it "un tramo más corto que la duración no ofrece nada y uno igual a la duración ofrece uno", :aggregate_failures do
      expect(find(free_set([ managua_time(9), managua_time(9, 20) ]))).to be_empty
      expect(managua_starts(find(free_set([ managua_time(9), managua_time(9, 30) ])))).to eq(%w[09:00])
    end

    it "sin tramos libres devuelve vacío" do
      expect(find(free_set)).to be_empty
    end

    it "no repite ni desordena inicios con varios tramos", :aggregate_failures do
      slots = find(free_set([ managua_time(9), managua_time(10) ], [ managua_time(9, 45), managua_time(11) ], [ managua_time(14), managua_time(15) ]))

      expect(slots.map(&:starts_at)).to eq(slots.map(&:starts_at).uniq.sort)
    end
  end

  describe "pasos que no dividen la hora ni el día" do
    it "paso de 7 minutos cruzando la medianoche local: 1435 y luego 0, no 1442" do
      free = free_set([ managua_time(23, 30), managua_time(0, 30, day: 6) ])

      slots = find(free, duration: 5, step: 7)

      expect(managua_starts(slots)).to eq(%w[23:34 23:41 23:48 23:55 00:00 00:07 00:14 00:21])
    end
  end

  describe "DST (America/New_York)" do
    it "primavera: los inicios inexistentes no son candidatos y la rejilla sigue en hora de pared (paso 50)" do
      # 2026-03-08 01:00 EST (06:00Z) to 05:00 EDT (09:00Z); wall minutes 100, 200 and 250 are the multiples of 50 that exist.
      free = free_set([ Time.utc(2026, 3, 8, 6), Time.utc(2026, 3, 8, 9) ])

      slots = find(free, zone: new_york, duration: 10, step: 50)

      expect(starts(slots)).to eq(%w[2026-03-08T06:40:00Z 2026-03-08T07:20:00Z 2026-03-08T08:10:00Z])
    end

    it "otoño: las dos ocurrencias de la hora repetida están en la rejilla" do
      # 01:00 EDT (05:00Z) to 02:30 EST (07:30Z).
      free = free_set([ Time.utc(2026, 11, 1, 5), Time.utc(2026, 11, 1, 7, 30) ])

      slots = find(free, zone: new_york, duration: 30, step: 30)

      expect(starts(slots)).to eq(%w[2026-11-01T05:00:00Z 2026-11-01T05:30:00Z 2026-11-01T06:00:00Z 2026-11-01T06:30:00Z 2026-11-01T07:00:00Z])
    end
  end

  describe "anticipación mínima" do
    it "con now a las 10:00 locales y 120 min de anticipación el primer inicio es 12:00" do
      slots = find(free_set([ managua_time(9), managua_time(18) ]), now: managua_time(10), lead: 120)

      expect(managua_starts(slots).first).to eq("12:00")
    end

    it "un inicio exactamente en now + anticipación entra y uno anterior no", :aggregate_failures do
      slots = find(free_set([ managua_time(9), managua_time(18) ]), now: managua_time(10, 5), lead: 120)

      expect(managua_starts(slots).first).to eq("12:15")
      expect(slots.map(&:starts_at)).to all(be >= managua_time(12, 5))
    end

    it "una anticipación que supera todo el tramo no deja huecos" do
      expect(find(free_set([ managua_time(9), managua_time(13) ]), now: managua_time(9), lead: 600)).to be_empty
    end
  end

  describe "anticipación máxima" do
    let(:free) { free_set([ managua_time(0), managua_time(0, day: 12) ]) }
    let(:now) { managua_time(8) }

    it "un inicio exactamente en now + N días entra y el siguiente paso no", :aggregate_failures do
      slots = find(free, now:, max_days: 2)

      expect(slots.last.starts_at).to eq(now + (2 * 86_400))
      expect(slots.map(&:starts_at)).not_to include(now + (2 * 86_400) + (15 * 60))
    end

    it "con 0 días solo cabe el inicio de ahora mismo si está en la rejilla" do
      expect(find(free, now:, max_days: 0).map(&:starts_at)).to eq([ now ])
    end
  end
end
