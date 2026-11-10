require "rails_helper"

# AUTHORIZATION is deny by default too. This spec walks ALL the router's routes (not a controller list): every action of
# an API controller authorizes (verify_authorized) except those in this allowlist, which are written, reasoned security
# decisions. A new action that skips the verification breaks here.
RSpec.describe "Autorización obligatoria por defecto (allowlist de skip_authorization!)" do
  # "Controller#action" => why it does not authorize a resource. Adding an entry is a security decision: reviewed in the PR.
  let(:allowlist) do
    {
      "Api::V1::Identity::SessionsController#create" => "login: aún no hay principal ni recurso de una organización",
      "Api::V1::Identity::SessionsController#show" => "devuelve la propia sesión del principal autenticado",
      "Api::V1::Identity::SessionsController#destroy" => "revoca la propia sesión",
      "Api::V1::Identity::SessionsController#destroy_all" => "revoca las propias sesiones",
      "Api::V1::Modules::MeController#show" => "devuelve el contexto y los permisos del propio principal; el contexto se resuelve con Access.with_context (membership validado)"
    }
  end

  let(:api_actions) do
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller

      klass = "#{controller.camelize}Controller".safe_constantize
      [ klass, route.defaults[:action] ] if klass && klass < Api::BaseController
    end.uniq
  end

  def skipped?(klass, action)
    klass.authorization_skips.any? do |skip|
      only = Array(skip[:only]).map(&:to_s)
      except = Array(skip[:except]).map(&:to_s)
      (only.empty? || only.include?(action)) && !except.include?(action)
    end
  end

  it "recorre las rutas reales de la API" do
    expect(api_actions.map { |klass, action| "#{klass.name}##{action}" }).to include("Api::V1::Access::OrganizationsController#index")
  end

  it "las acciones que no autorizan son EXACTAMENTE las de la allowlist" do
    skipped = api_actions.select { |klass, action| skipped?(klass, action) }.map { |klass, action| "#{klass.name}##{action}" }

    expect(skipped).to match_array(allowlist.keys)
  end

  it "cada skip declara un motivo no vacío" do
    reasons = api_actions.flat_map { |klass, _action| klass.authorization_skips.pluck(:reason) }

    expect(reasons).to all(satisfy { |reason| reason.to_s.strip.length > 10 })
  end

  it "la allowlist no tiene entradas obsoletas: cada una es una acción real" do
    existing = api_actions.map { |klass, action| "#{klass.name}##{action}" }

    expect(allowlist.keys - existing).to be_empty
  end

  it "skip_authorization! exige only: o except: (no existe el skip de todo el controlador)" do
    expect { Class.new(Api::BaseController) { skip_authorization!(reason: "motivo suficientemente largo") } }.to raise_error(ArgumentError, /only|except/)
  end
end
