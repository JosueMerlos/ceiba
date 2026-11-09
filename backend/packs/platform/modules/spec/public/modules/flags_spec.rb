require "rails_helper"

# Flipper (feature flags) con el actor `organization` (docs/architecture/05-module-system.md, "Tres conceptos"): un flag libera una
# FUNCIONALIDAD NUEVA por organización; nunca sustituye una activación (company_modules) ni un entitlement. Sin flags todavía.
RSpec.describe "Feature flags (Flipper)" do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  after { Flipper.features.each(&:remove) }

  it "tiene la versión fijada y persiste en la base (flipper-active_record)" do
    expect(Flipper::VERSION).to eq("1.4.2")
    expect(Flipper.adapter.adapter).to be_a(Flipper::Adapters::ActiveRecord)
  end

  it "no hay flags definidos todavía" do
    expect(Flipper.features).to be_empty
  end

  it "un flag que nadie definió está apagado para todas las organizaciones" do
    expect(Modules.flag_enabled?(:nueva_funcion, organization:)).to be(false)
  end

  it "activarlo para una organización no lo activa para otra (actor organization)" do
    Flipper.enable_actor(:nueva_funcion, Modules::FlagActor.new(organization.id))

    expect([ Modules.flag_enabled?(:nueva_funcion, organization:), Modules.flag_enabled?(:nueva_funcion, organization: other) ]).to eq([ true, false ])
  end

  it "acepta el id de la organización" do
    Flipper.enable_actor(:nueva_funcion, Modules::FlagActor.new(organization.id))

    expect(Modules.flag_enabled?(:nueva_funcion, organization: organization.id)).to be(true)
  end

  it "el actor se identifica como Organization;<id> (estable, no depende del modelo privado)" do
    expect(Modules::FlagActor.new("abc").flipper_id).to eq("Organization;abc")
  end

  it "un flag no activa un módulo: son conceptos distintos" do
    Flipper.enable(:appointments)
    company = create_in(organization, :company)

    expect(with_tenant(organization) { Modules.enabled?(company, "appointments") }).to be(false)
  end
end
