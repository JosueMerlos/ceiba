require "rails_helper"
require "benchmark"

# The public availability answer is cached for 30 s, AFTER the doors: the cache only ever holds the serialized 200 body, so
# a closed door (module, booking disabled, inactive branch) takes effect on the very next request even with a warm cache.
RSpec.describe "Caché de la disponibilidad pública" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    travel_to(Time.utc(2026, 11, 11, 12)) { example.run }
  ensure
    Rails.cache = original
  end

  before do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
  end

  def fetch(slug: world.company_a.slug, branch: world.branch_a1, services: [ service ], who: professional.id)
    ids = services.map(&:id).join(",")
    get "/api/public/v1/c/#{slug}/availability", params: { branch_id: branch.id, service_ids: ids, professional_id: who, from: "2026-11-16", to: "2026-11-16" }
  end

  # How many times the appointments table was read while the block ran.
  def appointment_reads(&)
    statements = []
    counter = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/FROM "appointments"/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    statements.size
  end

  it "una segunda petición idéntica dentro de 30 s sale de la caché: no vuelve a consultar las citas" do
    fetch
    first = response.parsed_body

    reads = appointment_reads { fetch }

    expect(reads).to eq(0)
    expect(response.parsed_body).to eq(first)
  end

  it "la primera petición sí consulta las citas (la comprobación no es vacía)" do
    expect(appointment_reads { fetch }).to be_positive
  end

  it "pasados 30 s se calcula de nuevo" do
    fetch
    travel 31.seconds

    expect(appointment_reads { fetch }).to be_positive
  end

  it "un instante antes de los 30 s todavía sale de la caché" do
    fetch
    travel 29.seconds

    expect(appointment_reads { fetch }).to eq(0)
  end

  it "otra sucursal de la misma empresa no reutiliza la caché" do
    fetch
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a2)

    reads = appointment_reads { fetch(branch: world.branch_a2) }

    expect(reads).to be_positive
  end

  it "otra empresa no reutiliza la caché" do
    fetch
    service_b = create_in(world.organization, :service, company: world.company_b)
    professional_b = create_in(world.organization, :professional, company: world.company_b)
    create_in(world.organization, :professional_branch_assignment, professional: professional_b, branch: world.branch_b1)
    create_in(world.organization, :professional_service, professional: professional_b, service: service_b)

    reads = appointment_reads { fetch(slug: world.company_b.slug, branch: world.branch_b1, services: [ service_b ], who: "any") }

    expect(reads).to be_positive
  end

  it "otro orden de servicios, otro profesional o otro rango no reutilizan la caché" do
    second = create_in(world.organization, :service, company: world.company_a)
    create_in(world.organization, :professional_service, professional:, service: second)
    fetch(services: [ service, second ])

    reads = [ -> { fetch(services: [ second, service ]) }, -> { fetch(services: [ service, second ], who: "any") } ].map { |request| appointment_reads(&request) }

    expect(reads).to all(be_positive)
  end

  it "apagar la reserva pública surte efecto al instante aunque la caché esté caliente" do
    fetch
    with_tenant(world.organization) { Modules::UpdateSettings.call(company: world.company_a, key: "appointments", settings: { "public_booking_enabled" => false }) }

    fetch

    expect(response).to have_http_status(:not_found)
  end

  it "con Redis caído y las opciones de producción el endpoint falla abierto: responde 200 calculado, sin caché y sin error", :aggregate_failures do
    Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(**RedisSettings.cache_store_options(url: "redis://127.0.0.1:1/15"))

    elapsed = Benchmark.realtime { 2.times { fetch } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("data" => be_an(Array), "meta" => be_a(Hash))
    expect(elapsed).to be < 2
  end

  it "una respuesta de error no se guarda: tras corregir la causa se calcula de verdad" do
    with_tenant(world.organization) { service.update!(active: false) }
    fetch
    expect(response).to have_http_status(:not_found)
    with_tenant(world.organization) { service.update!(active: true) }

    fetch

    expect(response).to have_http_status(:ok)
  end
end
