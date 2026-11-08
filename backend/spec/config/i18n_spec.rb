require "rails_helper"

# M0.04: i18n base del backend. Español de Nicaragua por defecto (rails-i18n) y UTC como zona de la app;
# la zona de cada sucursal es un dato (branches.time_zone), nunca la del servidor (docs/architecture/09).
RSpec.describe "Configuración de i18n y zona horaria" do
  it "usa es-NI como locale por defecto" do
    expect(I18n.default_locale).to eq(:"es-NI")
    expect(Rails.application.config.i18n.default_locale).to eq(:"es-NI")
  end

  it "declara los locales disponibles y rechaza los que no" do
    expect(I18n.available_locales).to contain_exactly(:"es-NI", :en)
    expect(I18n.enforce_available_locales).to be(true)
  end

  it "trae las traducciones de rails-i18n para es-NI (mensajes de validación y calendario)" do
    expect(I18n.t("errors.messages.blank")).to eq("no puede estar en blanco")
    expect(I18n.t("date.month_names")[1]).to eq("enero")
    expect(I18n.l(Date.new(2026, 11, 7), format: :long)).to include("noviembre")
  end

  it "traduce los nombres de atributos y errores de Active Record" do
    expect(I18n.t("activerecord.errors.messages.record_invalid", errors: "x")).to eq("La validación falló: x")
  end

  it "fija la zona horaria de la aplicación en UTC" do
    expect(Rails.application.config.time_zone).to eq("UTC")
    expect(Time.zone.name).to eq("UTC")
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
