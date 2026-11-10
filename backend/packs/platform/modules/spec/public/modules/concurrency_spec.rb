require "rails_helper"

# Carreras reales (COMMIT, hilos, conexiones distintas) entre activaciones de la misma empresa. La verificación de `requires` leía
# el estado y luego escribía sin serializar (sonda R2): Enable de un complemento y Disable de su base podían COMMIT a la vez y dejar
# un módulo activo sin lo que requiere. Enable y Disable serializan por empresa (pg_advisory_xact_lock).
RSpec.describe "Activaciones simultáneas de una empresa" do
  self.use_transactional_tests = false

  let!(:organization) { create(:organization) }
  let!(:company) { create_in(organization, :company) }

  after { purge_organizations([ organization ]) }

  def run_concurrently(*attempts)
    threads = attempts.map { |attempt| Thread.new { ApplicationRecord.connection_pool.with_connection { attempt.call } } }
    threads.map { |thread| thread.value rescue $! } # rubocop:disable Style/RescueModifier
  end

  def enable(key) = with_tenant(organization) { Modules::Enable.call(company:, key:) }
  def disable(key) = with_tenant(organization) { Modules::Disable.call(company:, key:) }
  def state = with_tenant(organization) { %w[sample sample_addon].to_h { |key| [ key, Modules.enabled?(company, key) ] } }

  # Alarga la ventana entre comprobar `requires` y hacer COMMIT: sin serializar, la otra transacción entra en ella.
  def slow_audit
    allow(Audit).to receive(:record).and_wrap_original do |original, **args|
      sleep 0.6 if args[:action] == "module.enabled"
      original.call(**args)
    end
  end

  it "Enable del complemento y Disable de su base a la vez: el resultado respeta `requires` y una de las dos se rechaza" do
    enable("sample")
    slow_audit
    results = run_concurrently(-> { enable("sample_addon") }, -> { sleep 0.2; disable("sample") })

    expect(state).not_to eq("sample" => false, "sample_addon" => true)
    expect(results.grep(Modules::Error).size).to eq(1)
  end

  it "Disable de la base y Enable del complemento a la vez, en el orden contrario" do
    enable("sample")
    slow_audit
    results = run_concurrently(-> { disable("sample") }, -> { sleep 0.2; enable("sample_addon") })

    expect(state).not_to eq("sample" => false, "sample_addon" => true)
    expect(results.select { |result| result.is_a?(Modules::ActivationResult) }.size).to be >= 1
  end

  it "dos Enable simultáneos de la primera fila: una fila, un hook, un evento y una auditoría" do
    allow(SampleModule::OnEnable).to receive(:call).and_wrap_original do |original, **args|
      sleep 0.5
      original.call(**args)
    end
    results = run_concurrently(-> { enable("sample") }, -> { sleep 0.1; enable("sample") })
    counts = with_tenant(organization) do
      [ Modules::CompanyModule.where(company_id: company.id).count, Events::OutboxEvent.where(name: "platform.module_enabled.v1").count, Audit::Event.where(action: "module.enabled").count ]
    end

    expect(results.map(&:changed)).to contain_exactly(true, false)
    expect([ counts, SampleModule.calls.size ]).to eq([ [ 1, 1, 1 ], 1 ])
  end
end
