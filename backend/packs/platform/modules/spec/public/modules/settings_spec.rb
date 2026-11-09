require "rails_helper"

# Criterios 5 y 6 de M0.09: settings con jerarquía default del esquema -> empresa -> sucursal, y escritura validada contra el
# esquema (422 con detalle por campo en la API; aquí, Modules::InvalidSettings con `errors`).
RSpec.describe "Settings de módulo" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:other_branch) { create_in(organization, :branch, company:) }
  let(:defaults) { Modules.registry.fetch("sample").defaults }

  before { with_tenant(organization) { Modules::Enable.call(company:, key: "sample") } }

  def settings_for(target_branch = nil) = with_tenant(organization) { Modules.settings_for("sample", company:, branch: target_branch) }

  def update(settings, target_branch = nil)
    with_tenant(organization) { Modules::UpdateSettings.call(company:, key: "sample", settings:, branch: target_branch) }
  end

  # Los errores por campo de una actualización rechazada.
  def rejected
    yield
    raise "se esperaba Modules::InvalidSettings"
  rescue Modules::InvalidSettings => error
    error.errors
  end

  describe "Modules.settings_for" do
    it "sin settings propios devuelve los defaults del esquema" do
      expect(settings_for).to eq("min_lead_time_minutes" => 120, "max_advance_days" => 60, "cancellation_window_hours" => 4, "public_booking_enabled" => true)
    end

    it "la empresa sobrescribe el default" do
      update("max_advance_days" => 30)

      expect(settings_for).to include("max_advance_days" => 30, "min_lead_time_minutes" => 120)
    end

    it "criterio 5: la sucursal con min_lead_time_minutes 60 lo devuelve; las demás y la empresa, el default (120)" do
      update({ "min_lead_time_minutes" => 60 }, branch)

      expect(settings_for(branch)["min_lead_time_minutes"]).to eq(60)
      expect(settings_for(other_branch)["min_lead_time_minutes"]).to eq(120)
      expect(settings_for["min_lead_time_minutes"]).to eq(120)
    end

    it "precedencia: default -> empresa -> sucursal" do
      update("min_lead_time_minutes" => 90, "max_advance_days" => 30)
      update({ "min_lead_time_minutes" => 45 }, branch)

      expect(settings_for(branch)).to include("min_lead_time_minutes" => 45, "max_advance_days" => 30)
      expect(settings_for(other_branch)).to include("min_lead_time_minutes" => 90)
    end

    it "ignora en la sucursal una clave que el esquema solo permite a nivel empresa (aunque la fila la traiga)" do
      with_tenant(organization) do
        Modules::BranchModuleSetting.create!(company_id: company.id, branch_id: branch.id, module_key: "sample", settings: { "cancellation_window_hours" => 99 })
      end

      expect(settings_for(branch)["cancellation_window_hours"]).to eq(4)
    end

    it "devuelve una copia: modificarla no altera el manifiesto" do
      settings_for["max_advance_days"] = 1

      expect(Modules.registry.fetch("sample").defaults["max_advance_days"]).to eq(60)
    end

    it "lanza NotEnabled si el módulo está inactivo en la empresa" do
      with_tenant(organization) { Modules::Disable.call(company:, key: "sample") }

      expect { settings_for }.to raise_error(Modules::NotEnabled)
    end

    it "rechaza una sucursal de otra empresa" do
      foreign = create_in(organization, :branch, company: create_in(organization, :company))

      expect { settings_for(foreign) }.to raise_error(ArgumentError, /sucursal/)
    end

    it "lanza InvalidSettings si lo guardado ya no cumple el esquema (evolución incompatible)" do
      with_tenant(organization) { Modules::CompanyModule.find_by!(company_id: company.id).update!(settings: { "max_advance_days" => 0 }) }

      expect { settings_for }.to raise_error(Modules::InvalidSettings, /max_advance_days/)
    end
  end

  describe "Modules::UpdateSettings" do
    it "guarda solo los overrides y devuelve los settings resueltos" do
      resolved = update("max_advance_days" => 30)

      expect(resolved).to include("max_advance_days" => 30, "min_lead_time_minutes" => 120)
      expect(with_tenant(organization) { Modules::CompanyModule.find_by!(company_id: company.id).settings }).to eq("max_advance_days" => 30)
    end

    it "combina con los overrides anteriores" do
      update("max_advance_days" => 30)
      update("min_lead_time_minutes" => 90)

      expect(settings_for).to include("max_advance_days" => 30, "min_lead_time_minutes" => 90)
    end

    it "un valor nulo quita el override y vuelve al default" do
      update("max_advance_days" => 30)
      update("max_advance_days" => nil)

      expect(settings_for["max_advance_days"]).to eq(60)
    end

    it "acepta claves simbólicas" do
      expect(update(max_advance_days: 31)["max_advance_days"]).to eq(31)
    end

    it "criterio 6: un valor inválido según el esquema da el detalle por campo y no guarda nada", :aggregate_failures do
      errors = rejected { update("min_lead_time_minutes" => -5, "public_booking_enabled" => "si") }

      expect(errors).to contain_exactly(
        { field: "min_lead_time_minutes", code: "minimum", message: "es menor que el mínimo permitido" },
        { field: "public_booking_enabled", code: "type", message: "no tiene el tipo esperado" }
      )
      expect(settings_for["min_lead_time_minutes"]).to eq(120)
    end

    it "rechaza una clave que el esquema no define" do
      errors = rejected { update("color_favorito" => "rojo") }

      expect(errors).to eq([ { field: "color_favorito", code: "unknown", message: "no es un ajuste de este módulo" } ])
    end

    it "criterio de la tarea: una clave NO permitida a nivel sucursal es un error en esa sucursal" do
      errors = rejected { update({ "cancellation_window_hours" => 2 }, branch) }

      expect(errors).to eq([ { field: "cancellation_window_hours", code: "not_allowed_at_level", message: "no se puede sobrescribir a nivel sucursal" } ])
    end

    it "esa misma clave sí se puede sobrescribir a nivel empresa" do
      expect(update("cancellation_window_hours" => 2)["cancellation_window_hours"]).to eq(2)
    end

    it "lanza NotEnabled con el módulo inactivo" do
      with_tenant(organization) { Modules::Disable.call(company:, key: "sample") }

      expect { update("max_advance_days" => 30) }.to raise_error(Modules::NotEnabled)
    end

    it "rechaza settings que no son un objeto" do
      expect { update([ 1 ]) }.to raise_error(ArgumentError, /Hash/)
    end

    it "una sucursal de otra empresa es un error de programación" do
      foreign = create_in(organization, :branch, company: create_in(organization, :company))

      expect { update({ "max_advance_days" => 3 }, foreign) }.to raise_error(ArgumentError, /sucursal/)
    end
  end

  describe "esquema con objetos anidados (appointments: reminders)" do
    let(:reminders_schema) do
      Modules::Registry.new.define(:anidado) do
        name "Anidado"
        version "1.0"
        settings_schema(type: "object", properties: { reminders: { type: "array", default: [], items: { type: "object", required: %w[kind offset_minutes],
                                                                                                           properties: { kind: { type: "string" }, offset_minutes: { type: "integer", minimum: 1 } } } } })
      end
    end

    it "reporta el campo anidado con su ruta" do
      value = [ { "kind" => "2h", "offset_minutes" => 0 }, { "kind" => "1h" } ]
      errors = Modules::SettingsValidator.call(reminders_schema, { "reminders" => value })

      expect(errors.pluck(:field)).to contain_exactly("reminders.0.offset_minutes", "reminders.1.offset_minutes")
    end
  end
end
