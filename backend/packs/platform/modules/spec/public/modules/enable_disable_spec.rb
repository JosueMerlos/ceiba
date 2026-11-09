require "rails_helper"

# Criterios 4 y 8 de M0.09: Enable/Disable idempotentes (una fila, on_enable una vez), con `requires`, eventos
# platform.module_enabled/disabled.v1 en la MISMA transacción, y desactivar no borra nada.
RSpec.describe "Modules::Enable y Modules::Disable" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }

  def enable(key = "sample", target: company) = with_tenant(organization) { Modules::Enable.call(company: target, key:) }
  def disable(key = "sample", target: company) = with_tenant(organization) { Modules::Disable.call(company: target, key:) }
  def rows(key = "sample") = with_tenant(organization) { Modules::CompanyModule.where(company_id: company.id, module_key: key).to_a }
  def events(name) = with_tenant(organization) { Events::OutboxEvent.where(name:).order(:id).map { |event| event.payload.symbolize_keys } }
  def enabled?(key = "sample") = with_tenant(organization) { Modules.enabled?(company, key) }

  describe Modules::Enable do
    it "activa el módulo: crea la fila, ejecuta on_enable y lo reporta como cambio" do
      result = enable

      expect(result).to have_attributes(key: "sample", company_id: company.id, changed: true)
      expect(rows).to contain_exactly(have_attributes(enabled_at: be_within(5.seconds).of(Time.current), disabled_at: nil, settings: {}))
      expect(SampleModule.calls).to eq([ [ :enable, company.id ] ])
      expect(enabled?).to be(true)
    end

    it "es idempotente (criterio 4): dos llamadas dejan UNA fila y on_enable se ejecutó UNA vez" do
      results = Array.new(2) { enable }

      expect(results.map(&:changed)).to eq([ true, false ])
      expect(rows.size).to eq(1)
      expect(SampleModule.calls.size).to eq(1)
    end

    it "emite platform.module_enabled.v1 una sola vez, con la empresa y el módulo" do
      2.times { enable }

      expect(events("platform.module_enabled.v1")).to eq([ { company_id: company.id, module: "sample" } ])
    end

    it "activar en una empresa no activa el módulo en otra" do
      enable

      expect(with_tenant(organization) { Modules.enabled?(other_company, "sample") }).to be(false)
    end

    it "exige que los módulos de `requires` estén activos en la empresa, y dice cuáles faltan" do
      expect { enable("sample_addon") }.to raise_error(Modules::RequirementsNotMet, /sample_addon.*sample/m)
      expect(rows("sample_addon")).to be_empty
      expect(SampleModule.calls).to be_empty
    end

    it "activa un módulo cuyos requisitos ya están activos" do
      enable

      expect(enable("sample_addon")).to have_attributes(changed: true)
    end

    it "no cuenta como requisito un módulo desactivado" do
      enable
      disable

      expect { enable("sample_addon") }.to raise_error(Modules::RequirementsNotMet)
    end

    it "rechaza un módulo que ningún manifiesto declara" do
      expect { enable("fantasma") }.to raise_error(Modules::UnknownModule, /fantasma/)
    end

    it "verifica el entitlement del plan (hoy siempre concedido: F6)" do
      allow(Modules).to receive(:entitled?).with(company, "sample").and_return(false)

      expect { enable }.to raise_error(Modules::NotEntitled, /sample/)
      expect(rows).to be_empty
    end

    it "si on_enable falla, no queda fila ni evento (misma transacción)" do
      allow(SampleModule::OnEnable).to receive(:call).and_raise("boom")

      expect { enable }.to raise_error("boom")
      expect(rows).to be_empty
      expect(events("platform.module_enabled.v1")).to be_empty
    end

    it "una carrera por la misma fila (otra transacción la creó entre la lectura y el INSERT) no duplica ni falla" do
      enable
      calls = 0
      allow(Modules::CompanyModule).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        calls == 1 ? nil : original.call(*args, **kwargs)
      end

      expect(enable).to have_attributes(changed: false)
      expect(rows.size).to eq(1)
    end

    it "rechaza una empresa de otra organización que la del contexto" do
      foreign = create_in(create(:organization), :company)

      expect { enable("sample", target: foreign) }.to raise_error(Modules::Error, /organización/)
    end
  end

  describe Modules::Disable do
    before { enable }

    it "desactiva: marca disabled_at, ejecuta on_disable y lo reporta como cambio" do
      result = disable

      expect(result).to have_attributes(key: "sample", company_id: company.id, changed: true)
      expect(rows).to contain_exactly(have_attributes(disabled_at: be_within(5.seconds).of(Time.current)))
      expect(SampleModule.calls.last).to eq([ :disable, company.id ])
      expect(enabled?).to be(false)
    end

    it "es idempotente: desactivar dos veces ejecuta on_disable y emite el evento UNA vez" do
      results = Array.new(2) { disable }

      expect(results.map(&:changed)).to eq([ true, false ])
      expect(SampleModule.calls.count { |call| call.first == :disable }).to eq(1)
      expect(events("platform.module_disabled.v1")).to eq([ { company_id: company.id, module: "sample" } ])
    end

    it "desactivar un módulo que nunca se activó no hace nada" do
      result = disable("sample", target: other_company)

      expect(result).to have_attributes(changed: false)
      expect(SampleModule.calls.count { |call| call.first == :disable }).to eq(0)
    end

    it "no deja desactivar un módulo que otro activo requiere" do
      enable("sample_addon")

      expect { disable }.to raise_error(Modules::RequiredByOthers, /sample_addon/)
      expect(enabled?).to be(true)
    end

    it "deja desactivar uno cuyo dependiente ya está desactivado" do
      enable("sample_addon")
      disable("sample_addon")

      expect(disable).to have_attributes(changed: true)
    end

    it "rechaza un módulo desconocido" do
      expect { disable("fantasma") }.to raise_error(Modules::UnknownModule)
    end

    it "si on_disable falla, el módulo sigue activo (misma transacción)" do
      allow(SampleModule::OnDisable).to receive(:call).and_raise("boom")

      expect { disable }.to raise_error("boom")
      expect(enabled?).to be(true)
    end
  end

  describe "reactivar (criterio 8)" do
    it "reutiliza la MISMA fila, refresca enabled_at, ejecuta on_enable de nuevo y emite otro evento" do
      enable
      original = rows.first
      disable
      result = enable

      expect(result).to have_attributes(changed: true)
      expect(rows).to contain_exactly(have_attributes(id: original.id, disabled_at: nil))
      expect(rows.first.enabled_at).to be >= original.enabled_at
      expect(SampleModule.calls.map(&:first)).to eq(%i[enable disable enable])
      expect(events("platform.module_enabled.v1").size).to eq(2)
    end

    it "conserva los settings de la empresa y los de sus sucursales" do
      enable
      branch = create_in(organization, :branch, company:)
      with_tenant(organization) do
        Modules::CompanyModule.find_by!(company_id: company.id, module_key: "sample").update!(settings: { "max_advance_days" => 30 })
        Modules::BranchModuleSetting.create!(company_id: company.id, branch_id: branch.id, module_key: "sample", settings: { "min_lead_time_minutes" => 60 })
      end

      disable
      enable

      expect(with_tenant(organization) { [ Modules::CompanyModule.find_by(module_key: "sample").settings, Modules::BranchModuleSetting.find_by(module_key: "sample").settings ] })
        .to eq([ { "max_advance_days" => 30 }, { "min_lead_time_minutes" => 60 } ])
    end
  end

  describe "Modules.entitled?" do
    it "devuelve true hasta que existan los planes (F6)" do
      expect(Modules.entitled?(company, "sample")).to be(true)
    end
  end
end
