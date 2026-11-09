require "rails_helper"

# Criterio 5: una acción de controlador sin `authorize` falla en test (verify_authorized), un index sin policy_scope falla
# (verify_policy_scoped), y la excepción de una acción que no autoriza es explícita, con motivo y en una allowlist.
RSpec.describe "verify_authorized y verify_policy_scoped globales" do
  before(:context) do # rubocop:disable RSpec/BeforeAfterAll -- dibujar rutas es caro y global
    Object.const_set(:AccessProbes, Module.new) unless Object.const_defined?(:AccessProbes)
    AccessProbes.const_set(:AllowPolicy, Class.new(Access::BasePolicy) { def show? = true }) unless AccessProbes.const_defined?(:AllowPolicy, false)
    AccessProbes.const_set(:ProbesController, Class.new(Api::BaseController) do
      skip_authorization! reason: "probe de test: la acción exempt no devuelve recursos", only: :exempt

      def unauthorized = render(json: { data: { ok: true } })
      def exempt = render(json: { data: { ok: true } })
      def authorized
        authorize Object.new, :show?, policy_class: AccessProbes::AllowPolicy
        render json: { data: { ok: true } }
      end

      # Acción de colección que NO se llama index: también debe usar policy_scope.
      def search
        authorize Tenancy::Directory.organizations_for([]), :index?, policy_class: Access::OrganizationPolicy
        render json: { data: [] }
      end

      def member
        authorize Object.new, :show?, policy_class: AccessProbes::AllowPolicy
        render json: { data: { ok: true } }
      end

      def scoped_search
        authorize Tenancy::Directory.organizations_for([]), :index?, policy_class: Access::OrganizationPolicy
        render json: { data: policy_scope(Tenancy::Directory.organizations_for([]), policy_scope_class: Access::OrganizationPolicy::Scope).to_a }
      end

      def index
        authorize Tenancy::Directory.organizations_for([]), :index?, policy_class: Access::OrganizationPolicy
        render json: { data: [] }
      end
    end) unless AccessProbes.const_defined?(:ProbesController, false)

    Rails.application.reload_routes_unless_loaded
    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      scope path: "api/v1/access_probes", controller: "access_probes/probes" do
        get "unauthorized"
        get "authorized"
        get "exempt"
        get "index"
        get "search"
        get "member"
        get "scoped_search"
      end
    end
  ensure
    Rails.application.routes.disable_clear_and_finalize = false
  end
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll

  before { sign_in }

  it "una acción que no autoriza responde 500 (bug) y NO entrega su cuerpo" do
    get "/api/v1/access_probes/unauthorized"

    expect(response).to have_http_status(:internal_server_error)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.parsed_body).not_to have_key("data")
  end

  it "la verificación lanza Pundit::AuthorizationNotPerformedError (queda en el log del servidor)" do
    allow(Api::ErrorReporter).to receive(:call)

    get "/api/v1/access_probes/unauthorized"

    expect(Api::ErrorReporter).to have_received(:call).with(instance_of(Pundit::AuthorizationNotPerformedError), any_args)
  end

  it "una acción que autoriza responde normal" do
    get "/api/v1/access_probes/authorized"

    expect(response).to have_http_status(:ok)
  end

  it "un index que autoriza pero no usa policy_scope falla (verify_policy_scoped)" do
    allow(Api::ErrorReporter).to receive(:call)

    get "/api/v1/access_probes/index"

    expect(response).to have_http_status(:internal_server_error)
    expect(Api::ErrorReporter).to have_received(:call).with(instance_of(Pundit::PolicyScopingNotPerformedError), any_args)
  end

  it "una acción de colección que no se llama index también exige policy_scope" do
    allow(Api::ErrorReporter).to receive(:call)

    get "/api/v1/access_probes/search"

    expect(response).to have_http_status(:internal_server_error)
    expect(Api::ErrorReporter).to have_received(:call).with(instance_of(Pundit::PolicyScopingNotPerformedError), any_args)
  end

  it "una acción de colección con policy_scope responde normal" do
    get "/api/v1/access_probes/scoped_search"

    expect(response).to have_http_status(:ok)
  end

  it "autorizar un registro concreto no exige policy_scope (acciones de miembro)" do
    get "/api/v1/access_probes/member"

    expect(response).to have_http_status(:ok)
  end

  it "skip_authorization! exige un motivo y deja constancia" do
    expect { Class.new(Api::BaseController) { skip_authorization!(reason: " ", only: :x) } }.to raise_error(ArgumentError, /motivo|reason/)
    expect(AccessProbes::ProbesController.authorization_skips).to include(a_hash_including(reason: a_string_matching(/probe/)))
  end
end
