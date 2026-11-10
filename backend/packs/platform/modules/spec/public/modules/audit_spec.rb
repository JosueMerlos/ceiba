require "rails_helper"

# Hand-off de M0.11: Enable, Disable y UpdateSettings auditan con Audit.record en la MISMA transacción (si algo falla no queda ni
# el cambio ni el evento de auditoría) y solo cuando hubo un cambio real (una repetición idempotente no audita).
RSpec.describe "Auditoría de módulos" do
  let(:world) { build_access_world }
  let(:organization) { world.organization }
  let(:company) { world.company_a }
  let(:manager) { user_with_role("org_admin", world) }

  def enable(target = company) = with_tenant(organization) { Modules::Enable.call(company: target, key: "sample") }
  def disable = with_tenant(organization) { Modules::Disable.call(company:, key: "sample") }
  def audits(action = nil) = with_tenant(organization) { Audit::Event.where(action ? { action: } : {}).order(:created_at, :id).to_a }

  describe "module.enabled / module.disabled" do
    it "activar audita module.enabled sobre la fila de company_modules, con el antes y el después" do
      enable
      row = with_tenant(organization) { Modules::CompanyModule.find_by!(company_id: company.id, module_key: "sample") }

      expect(audits("module.enabled")).to contain_exactly(
        have_attributes(auditable_type: "Modules::CompanyModule", auditable_id: row.id, before: { "active" => false }, after: { "active" => true },
                        metadata: { "module" => "sample", "company_id" => company.id })
      )
    end

    it "desactivar audita module.disabled" do
      enable
      disable

      expect(audits("module.disabled")).to contain_exactly(have_attributes(before: { "active" => true }, after: { "active" => false }))
    end

    it "una repetición idempotente no audita" do
      2.times { enable }
      2.times { disable }

      expect(audits.map(&:action)).to eq(%w[module.enabled module.disabled])
    end

    it "reactivar audita otra vez module.enabled sobre la misma fila" do
      enable
      disable
      enable

      expect(audits("module.enabled").map(&:auditable_id).uniq.size).to eq(1)
      expect(audits("module.enabled").size).to eq(2)
    end

    it "el actor es el principal de la request" do
      principal = access_principal_for(manager, organization)
      Current.set(principal:) { enable }

      expect(audits("module.enabled").first).to have_attributes(actor_type: "user", actor_id: manager.id)
    end

    it "sin principal (un job, la provisión) el actor es el sistema" do
      enable

      expect(audits("module.enabled").first).to have_attributes(actor_type: "system", actor_id: nil)
    end

    it "si on_enable falla no queda auditoría (misma transacción)" do
      allow(SampleModule::OnEnable).to receive(:call).and_raise("boom")

      expect { enable }.to raise_error("boom")
      expect(audits).to be_empty
    end

    it "si falla la propia auditoría, no queda activado" do
      allow(Audit).to receive(:record).and_raise("sin auditoría")

      expect { enable }.to raise_error("sin auditoría")
      expect(with_tenant(organization) { Modules.enabled?(company, "sample") }).to be(false)
    end
  end

  describe "module.settings_updated" do
    before { enable }

    def update(settings, branch = nil) = with_tenant(organization) { Modules::UpdateSettings.call(company:, key: "sample", settings:, branch:) }

    it "audita solo las claves que cambiaron, con su valor anterior y el nuevo (sin enmascarar)" do
      update("max_advance_days" => 30)
      update("max_advance_days" => 45, "min_lead_time_minutes" => 90)

      expect(audits("module.settings_updated").last).to have_attributes(
        before: { "max_advance_days" => 30, "min_lead_time_minutes" => nil }.compact,
        after: { "max_advance_days" => 45, "min_lead_time_minutes" => 90 },
        metadata: { "module" => "sample", "company_id" => company.id, "level" => "company" }
      )
    end

    it "una sucursal audita su nivel y su id" do
      update({ "min_lead_time_minutes" => 60 }, world.branch_a1)

      expect(audits("module.settings_updated").last).to have_attributes(
        auditable_type: "Modules::BranchModuleSetting",
        metadata: { "module" => "sample", "company_id" => company.id, "level" => "branch", "branch_id" => world.branch_a1.id }
      )
    end

    it "no audita si los settings no cambian" do
      update("max_advance_days" => 30)

      expect { update("max_advance_days" => 30) }.not_to(change { audits("module.settings_updated").size })
    end

    it "ninguna clave de appointments queda enmascarada por el criterio de la auditoría" do
      manifest = Modules.registry.fetch("appointments")
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + [ /digest/i, /csrf/i, /ciphertext/i ])

      expect(manifest.setting_keys.reject { |key| filter.filter(key => 1)[key] == 1 }).to be_empty
    end
  end

  describe "el manifiesto no admite settings que la auditoría enmascararía" do
    it "rechaza una propiedad cuyo nombre es sensible (p. ej. whatsapp_token)" do
      expect do
        Modules::Registry.new.define(:secreto) do
          name "Secreto"
          version "1.0"
          settings_schema(type: "object", properties: { whatsapp_token: { type: "string", maxLength: 100, default: "" } })
        end
      end.to raise_error(Modules::InvalidManifest, /"whatsapp_token".*auditor/m)
    end
  end
end
