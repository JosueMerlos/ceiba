require "rails_helper"

RSpec.describe Appointments::Availability::Calculator do
  let(:managua) { "America/Managua" }
  let(:new_york) { "America/New_York" }

  def slot(weekday, from, to) = Appointments::Availability::WeeklySlot.new(weekday:, starts_minute: from * 60, ends_minute: to * 60)

  def interval(from, to) = Appointments::Availability::Interval.new(starts_at: from, ends_at: to)

  # Managua wall-clock (UTC-6, no DST) as a UTC instant. Monday is 2026-01-05.
  def managua_time(hour, minute = 0, day: 5) = Time.utc(2026, 1, day) + (((hour + 6) * 60) + minute) * 60

  def plan(duration = 30, before: 0, after: 0, kind: nil)
    Appointments::Availability::ServicePlan.new(duration_minutes: duration, buffer_before_minutes: before, buffer_after_minutes: after, price_minor: 0,
                                                currency: "NIO", required_kind: kind)
  end

  def person(id, slots: [ slot(1, 9, 13) ], time_offs: [], busy: []) = { id:, slots:, time_offs:, busy: }

  def room(id, slots: [], time_offs: [], busy: [], kind: "room") = { id:, kind:, slots:, time_offs:, busy: }

  # `professional_slots`, `time_offs`, `busy` and `duration_minutes` describe the single professional "p1" of the base case.
  def calculate(overrides = {})
    legacy = overrides.slice(:professional_slots, :time_offs, :busy, :duration_minutes)
    options = overrides.except(*legacy.keys)
    professionals = [ person("p1", slots: legacy.fetch(:professional_slots, [ slot(1, 9, 13) ]), time_offs: legacy.fetch(:time_offs, []), busy: legacy.fetch(:busy, [])) ]
    described_class.call(
      **{ branch_slots: [ slot(1, 9, 13) ], professionals:, resources: [], plan: plan(legacy.fetch(:duration_minutes, 30)),
          load_by_day: {}, time_zone: managua, from_date: Date.new(2026, 1, 5), to_date: Date.new(2026, 1, 5), step_minutes: 15,
          now: Time.utc(2026, 1, 1), min_lead_minutes: 0, max_advance_days: 60 }.merge(options)
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

  describe "varios profesionales y :any" do
    def labels_with_pro(slots) = slots.map { |s| [ s.starts_at.in_time_zone(managua).strftime("%H:%M"), s.professional_id ] }

    it "dos profesionales libres a las 10:00, el de menos citas ese día se asigna (carga p1 = 3, p2 = 1)" do
      load = { "p1" => { Date.new(2026, 1, 5) => 3 }, "p2" => { Date.new(2026, 1, 5) => 1 } }

      slots = calculate(professionals: [ person("p1"), person("p2") ], load_by_day: load, step_minutes: 60)

      expect(labels_with_pro(slots)).to eq([ [ "09:00", "p2" ], [ "10:00", "p2" ], [ "11:00", "p2" ], [ "12:00", "p2" ] ])
    end

    it "cuando el de menos carga está ocupado en un inicio, ese inicio va al otro; cada inicio sale una sola vez", :aggregate_failures do
      load = { "p1" => { Date.new(2026, 1, 5) => 3 }, "p2" => { Date.new(2026, 1, 5) => 1 } }
      busy = [ interval(managua_time(10), managua_time(11)) ]

      slots = calculate(professionals: [ person("p1"), person("p2", busy:) ], load_by_day: load, step_minutes: 60)

      expect(labels_with_pro(slots)).to eq([ [ "09:00", "p2" ], [ "10:00", "p1" ], [ "11:00", "p2" ], [ "12:00", "p2" ] ])
    end

    it "con la misma carga gana el menor id, sin importar el orden de entrada", :aggregate_failures do
      slots = calculate(professionals: [ person("p2"), person("p1") ], step_minutes: 60)

      expect(slots.map(&:professional_id).uniq).to eq([ "p1" ])
      expect(slots.size).to eq(4)
    end

    it "la carga cuenta por día local: la de otro día no pesa", :aggregate_failures do
      schedule = [ slot(1, 9, 10), slot(2, 9, 10) ]
      load = { "p1" => { Date.new(2026, 1, 5) => 2 }, "p2" => { Date.new(2026, 1, 6) => 2 } }

      slots = calculate(branch_slots: schedule, professionals: [ person("p1", slots: schedule), person("p2", slots: schedule) ], load_by_day: load,
                        to_date: Date.new(2026, 1, 6), duration_minutes: 60, step_minutes: 60)

      expect(slots.map { [ it.starts_at.in_time_zone(managua).day, it.professional_id ] }).to eq([ [ 5, "p2" ], [ 6, "p1" ] ])
    end

    it "los profesionales con horario distinto aportan sus propios inicios, ordenados por hora", :aggregate_failures do
      early = person("p1", slots: [ slot(1, 9, 10) ])
      late = person("p2", slots: [ slot(1, 12, 13) ])

      slots = calculate(professionals: [ late, early ], step_minutes: 30)

      expect(labels_with_pro(slots)).to eq([ [ "09:00", "p1" ], [ "09:30", "p1" ], [ "12:00", "p2" ], [ "12:30", "p2" ] ])
    end

    it "sin profesionales no hay huecos" do
      expect(calculate(professionals: [])).to be_empty
    end

    it "los huecos duran la duración total del plan, no incluyen buffers (corte 50 con buffer posterior de 10)", :aggregate_failures do
      slots = calculate(plan: plan(50, after: 10), step_minutes: 60)

      expect(managua_labels(slots)).to eq([ "05 09:00", "05 10:00", "05 11:00", "05 12:00" ])
      expect(slots.map { it.ends_at - it.starts_at }.uniq).to eq([ 3000.0 ])
    end

    it "buffer previo de 10 y posterior de 10 sobre 9-13 con duración 30: del 09:15 al 12:15" do
      slots = calculate(plan: plan(30, before: 10, after: 10))

      expect(managua_labels(slots).then { [ it.first, it.last, it.size ] }).to eq([ "05 09:15", "05 12:15", 13 ])
    end
  end

  describe "recursos" do
    def with_room(resources, **options) = calculate(resources:, plan: plan(kind: "room"), step_minutes: 30, **options)

    def rooms_at(slots) = slots.map { [ it.starts_at.in_time_zone(managua).strftime("%H:%M"), it.resource_id ] }

    it "la única sala ocupada a las 11:00 quita ese inicio aunque haya dos profesionales libres" do
      busy = [ interval(managua_time(11), managua_time(11, 30)) ]

      slots = with_room([ room("r1", busy:) ], professionals: [ person("p1"), person("p2") ])

      expect(rooms_at(slots).map(&:first)).to eq(%w[09:00 09:30 10:00 10:30 11:30 12:00 12:30])
    end

    it "con dos salas y una ocupada a las 11:00, ese inicio sale con la otra y cada resto con la de menor id", :aggregate_failures do
      busy = [ interval(managua_time(11), managua_time(11, 30)) ]

      slots = with_room([ room("r2"), room("r1", busy:) ])

      expect(rooms_at(slots)).to include([ "11:00", "r2" ], [ "10:30", "r1" ], [ "11:30", "r1" ])
      expect(slots.size).to eq(8)
    end

    it "sin requisito de recurso el resource_id es nulo aunque existan recursos" do
      slots = calculate(resources: [ room("r1") ])

      expect(slots.map(&:resource_id).uniq).to eq([ nil ])
    end

    it "un recurso de otro tipo no satisface el requisito" do
      expect(with_room([ room("c1", kind: "chair") ])).to be_empty
    end

    it "pedir un tipo sin ningún recurso candidato no deja huecos" do
      expect(with_room([])).to be_empty
    end

    it "una ausencia del recurso lo quita de ese tramo (sala ausente 10:00-11:00)" do
      off = [ interval(managua_time(10), managua_time(11)) ]

      expect(rooms_at(with_room([ room("r1", time_offs: off) ])).map(&:first)).to eq(%w[09:00 09:30 11:00 11:30 12:00 12:30])
    end

    it "un recurso sin franjas propias sigue el horario de la sucursal" do
      slots = with_room([ room("r1", slots: []) ], professionals: [ person("p1", slots: [ slot(1, 9, 13) ]) ])

      expect(slots.size).to eq(8)
    end

    it "las franjas propias del recurso lo restringen (sala 10-12, sucursal y profesional 9-13)" do
      slots = with_room([ room("r1", slots: [ slot(1, 10, 12) ]) ])

      expect(rooms_at(slots).map(&:first)).to eq(%w[10:00 10:30 11:00 11:30])
    end

    it "adversarial: un recurso con franjas de otro día de la semana no ofrece nada ese lunes" do
      expect(with_room([ room("r1", slots: [ slot(2, 9, 13) ]) ])).to be_empty
    end

    it "el buffer posterior se cuenta también contra la ocupación del recurso (sala ocupada 12:00-12:30)", :aggregate_failures do
      busy = [ interval(managua_time(12), managua_time(12, 30)) ]

      slots = calculate(resources: [ room("r1", busy:) ], plan: plan(30, after: 10, kind: "room"), step_minutes: 15,
                        professionals: [ person("p1", slots: [ slot(1, 11, 13) ]) ])

      expect(managua_labels(slots)).to eq([ "05 11:00", "05 11:15" ])
    end

    it "el recurso y el profesional deben estar libres a la vez: sala libre solo 10:00-11:00, profesional libre 10:30-13:00" do
      busy_pro = person("p1", slots: [ slot(1, 10, 13) ], busy: [ interval(managua_time(10), managua_time(10, 30)) ])

      slots = with_room([ room("r1", slots: [ slot(1, 10, 11) ]) ], professionals: [ busy_pro ])

      expect(rooms_at(slots)).to eq([ [ "10:30", "r1" ] ])
    end
  end
end
