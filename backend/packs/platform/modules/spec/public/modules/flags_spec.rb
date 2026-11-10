require "rails_helper"

# Flipper feature flags with the `organization` actor: a flag releases a NEW FEATURE per organization; it never replaces an
# activation (company_modules) or an entitlement.
RSpec.describe "Feature flags (Flipper)" do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  # `flipper/test_help` makes test use an in-memory adapter cleared on every example; other environments use
  # flipper-active_record, so these examples run against the real database.
  it "tiene la versión fijada" do
    expect(Flipper::VERSION).to eq("1.4.2")
  end

  it "persiste en la base con flipper-active_record (tablas flipper_features y flipper_gates)" do
    flipper = Flipper.new(Flipper::Adapters::ActiveRecord.new)
    flipper.enable_actor(:persistido, Modules::FlagActor.new(organization.id))

    expect([ flipper.enabled?(:persistido, Modules::FlagActor.new(organization.id)), flipper.enabled?(:persistido, Modules::FlagActor.new(other.id)) ]).to eq([ true, false ])
  end

  it "Flipper no precarga todos los flags en cada request (ni en /api/health) mientras no existan flags" do
    memoizer = Rails.application.middleware.find { |middleware| middleware.klass == Flipper::Middleware::Memoizer }

    expect(memoizer.args.first[:preload]).to be(false)
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
