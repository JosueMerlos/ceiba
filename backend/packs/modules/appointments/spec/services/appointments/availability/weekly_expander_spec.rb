require "rails_helper"

RSpec.describe Appointments::Availability::WeeklyExpander do
  let(:new_york) { "America/New_York" }

  def slot(weekday, from, to) = Appointments::Availability::WeeklySlot.new(weekday:, starts_minute: from * 60, ends_minute: to * 60)

  def slot_minutes(weekday, from, to) = Appointments::Availability::WeeklySlot.new(weekday:, starts_minute: from, ends_minute: to)

  def expand(slots, zone, from, to) = described_class.call(slots:, time_zone: zone, from_date: from, to_date: to)

  def utc_pairs(interval_set) = interval_set.intervals.map { |i| [ i.starts_at.utc.iso8601, i.ends_at.utc.iso8601 ] }

  describe "día normal" do
    it "convierte lunes 09:00-13:00 de America/Managua (UTC-6 fijo) a 15:00-19:00Z" do
      result = expand([ slot(1, 9, 13) ], "America/Managua", Date.new(2026, 1, 5), Date.new(2026, 1, 5))

      expect(utc_pairs(result)).to eq([ [ "2026-01-05T15:00:00Z", "2026-01-05T19:00:00Z" ] ])
    end

    it "ignora las franjas de otros días de la semana y devuelve vacío" do
      result = expand([ slot(2, 9, 13) ], "America/Managua", Date.new(2026, 1, 5), Date.new(2026, 1, 5))

      expect(result).to be_empty
    end

    it "expande cada fecha del rango con las franjas de su día", :aggregate_failures do
      result = expand([ slot(1, 9, 10), slot(2, 14, 15), slot(1, 16, 17) ], "America/Managua", Date.new(2026, 1, 5), Date.new(2026, 1, 12))

      expect(utc_pairs(result)).to eq(
        [ [ "2026-01-05T15:00:00Z", "2026-01-05T16:00:00Z" ], [ "2026-01-05T22:00:00Z", "2026-01-05T23:00:00Z" ],
          [ "2026-01-06T20:00:00Z", "2026-01-06T21:00:00Z" ],
          [ "2026-01-12T15:00:00Z", "2026-01-12T16:00:00Z" ], [ "2026-01-12T22:00:00Z", "2026-01-12T23:00:00Z" ] ]
      )
    end

    it "sin franjas devuelve vacío" do
      expect(expand([], "America/Managua", Date.new(2026, 1, 5), Date.new(2026, 1, 11))).to be_empty
    end
  end

  describe "domingo del cambio de horario de primavera (2026-03-08, America/New_York)" do
    let(:schedule) { [ slot(0, 9, 17), slot(1, 9, 17), slot(6, 9, 17) ] }

    it "9-17 locales caen en 13:00-21:00Z el domingo, igual el lunes, y 14:00-22:00Z el sábado anterior", :aggregate_failures do
      expect(utc_pairs(expand(schedule, new_york, Date.new(2026, 3, 8), Date.new(2026, 3, 8)))).to eq([ [ "2026-03-08T13:00:00Z", "2026-03-08T21:00:00Z" ] ])
      expect(utc_pairs(expand(schedule, new_york, Date.new(2026, 3, 9), Date.new(2026, 3, 9)))).to eq([ [ "2026-03-09T13:00:00Z", "2026-03-09T21:00:00Z" ] ])
      expect(utc_pairs(expand(schedule, new_york, Date.new(2026, 3, 7), Date.new(2026, 3, 7)))).to eq([ [ "2026-03-07T14:00:00Z", "2026-03-07T22:00:00Z" ] ])
    end

    it "01:00-04:00 (cubre la hora inexistente) dura 2 h reales: 06:00Z-08:00Z" do
      expect(utc_pairs(expand([ slot(0, 1, 4) ], new_york, Date.new(2026, 3, 8), Date.new(2026, 3, 8)))).to eq([ [ "2026-03-08T06:00:00Z", "2026-03-08T08:00:00Z" ] ])
    end

    it "02:00-02:45 (entera dentro del hueco) se descarta sin excepción" do
      expect(expand([ slot_minutes(0, 120, 165) ], new_york, Date.new(2026, 3, 8), Date.new(2026, 3, 8))).to be_empty
    end

    it "01:00-02:30 (termina en el hueco) se recorta a la transición: 06:00Z-07:00Z" do
      result = expand([ slot_minutes(0, 60, 150) ], new_york, Date.new(2026, 3, 8), Date.new(2026, 3, 8))

      expect(utc_pairs(result)).to eq([ [ "2026-03-08T06:00:00Z", "2026-03-08T07:00:00Z" ] ])
    end

    it "02:30-03:15 (empieza en el hueco) arranca en la transición: 07:00Z-07:15Z" do
      result = expand([ slot_minutes(0, 150, 195) ], new_york, Date.new(2026, 3, 8), Date.new(2026, 3, 8))

      expect(utc_pairs(result)).to eq([ [ "2026-03-08T07:00:00Z", "2026-03-08T07:15:00Z" ] ])
    end
  end

  describe "domingo del cambio de horario de otoño (2026-11-01, America/New_York)" do
    it "9-17 locales caen en 14:00Z-22:00Z" do
      expect(utc_pairs(expand([ slot(0, 9, 17) ], new_york, Date.new(2026, 11, 1), Date.new(2026, 11, 1)))).to eq([ [ "2026-11-01T14:00:00Z", "2026-11-01T22:00:00Z" ] ])
    end

    it "01:00-04:00 (cubre la hora repetida) dura 4 h reales: 05:00Z-09:00Z" do
      expect(utc_pairs(expand([ slot(0, 1, 4) ], new_york, Date.new(2026, 11, 1), Date.new(2026, 11, 1)))).to eq([ [ "2026-11-01T05:00:00Z", "2026-11-01T09:00:00Z" ] ])
    end

    it "01:30-03:00 abre en la primera ocurrencia de 01:30: 05:30Z-08:00Z (2 h 30 reales)" do
      result = expand([ slot_minutes(0, 90, 180) ], new_york, Date.new(2026, 11, 1), Date.new(2026, 11, 1))

      expect(utc_pairs(result)).to eq([ [ "2026-11-01T05:30:00Z", "2026-11-01T08:00:00Z" ] ])
    end

    it "00:00-01:30 cierra en la primera ocurrencia de 01:30: 04:00Z-05:30Z (1 h 30 reales)" do
      result = expand([ slot_minutes(0, 0, 90) ], new_york, Date.new(2026, 11, 1), Date.new(2026, 11, 1))

      expect(utc_pairs(result)).to eq([ [ "2026-11-01T04:00:00Z", "2026-11-01T05:30:00Z" ] ])
    end
  end
end
