require "rails_helper"

# Flipper (feature flags) con el actor `organization` (docs/architecture/05-module-system.md, "Tres conceptos"): un flag libera una
# FUNCIONALIDAD NUEVA por organización; nunca sustituye una activación (company_modules) ni un entitlement. Sin flags todavía.
RSpec.describe "Feature flags (Flipper)" do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  # Flipper trae `flipper/test_help`: en test usa un adaptador de memoria que se vacía en cada ejemplo. En el resto de entornos el
  # adaptador es flipper-active_record (config/initializers/flipper.rb de modules); aquí se prueba contra la base real.
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
