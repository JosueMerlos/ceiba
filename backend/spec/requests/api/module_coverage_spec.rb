require "rails_helper"

# Suite de COBERTURA DE MÓDULOS (docs/architecture/12-testing-strategy.md, playbook de módulos). Un pack de módulos nuevo entra solo:
#   1. ESTÁTICA: todo controlador de packs/modules/<key>/app/controllers declara `requires_module :<key>` (su propio módulo).
#   2. DINÁMICA: toda ruta cuyo controlador declara un módulo responde 404 cuando ese módulo está inactivo en la empresa, y deja de
#      responder 404 cuando se activa (la prueba no es vacía).
# Hoy los módulos reales no tienen controladores (F1); la suite se ejercita con las rutas del módulo ficticio `sample`.
RSpec.describe "Cobertura de módulos: rutas de un módulo inactivo => 404" do
  include_context "con rutas de sample"
  include_context "con el módulo sample sincronizado"

  # Controladores de packs/modules/*: { clase => key del pack }.
  def module_controllers
    Rails.root.glob("packs/modules/*/app/controllers/**/*_controller.rb").to_h do |file|
      key = file.relative_path_from(Rails.root.join("packs/modules")).each_filename.first
      relative = file.relative_path_from(Rails.root.join("packs/modules/#{key}/app/controllers")).to_s.delete_suffix(".rb")
      [ relative.camelize.constantize, key ]
    end
  end

  # Rutas reales (y las de sample, dibujadas por el contexto) cuyo controlador exige un módulo.
  def module_routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      klass = controller && "#{controller.camelize}Controller".safe_constantize
      next unless klass.respond_to?(:required_module) && klass.required_module

      { klass:, module: klass.required_module, verb: route.verb.presence || "GET", spec: route.path.spec.to_s.delete_suffix("(.:format)") }
    end
  end

  def url_for_route(spec, company)
    spec.gsub(":organization_id", company.organization_id).gsub(":company_id", company.id).gsub(/:\w+/, SampleModule::UNKNOWN_ID)
  end

  let(:world) { build_access_world }
  let(:company) { world.company_a }
  let(:manager) { sign_in(user_with_role("company_manager", world, company:)) }

  describe "estática" do
    it "todo controlador de un pack de módulos declara requires_module con la key de su propio pack" do
      wrong = module_controllers.reject { |klass, key| klass.respond_to?(:required_module) && klass.required_module == key }

      expect(wrong.keys).to be_empty, "controladores sin `requires_module :<key>` de su pack: #{wrong.keys.map(&:name).join(', ')}"
    end

    it "la comprobación detecta un controlador que no lo declara (no es vacía)" do
      leaky = Class.new(Api::BaseController)
      declared = Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :sample }

      expect([ leaky, declared ].reject { |klass| klass.respond_to?(:required_module) && klass.required_module == "sample" }).to eq([ leaky ])
    end
  end

  describe "dinámica" do
    it "encuentra las rutas con módulo (incluida la de sample)" do
      expect(module_routes.pluck(:module)).to include("sample")
    end

    it "con el módulo inactivo, TODAS responden 404 problem+json" do
      manager
      statuses = module_routes.map do |route|
        process(route[:verb].downcase.to_sym, url_for_route(route[:spec], company), headers: manager.csrf_headers, as: :json)
        [ route[:spec], response.status, response.parsed_body["code"] ]
      end

      expect(statuses).to all(satisfy { |_spec, status, code| status == 404 && code == "resource.not_found" })
    end

    it "con el módulo activo dejan de ser 404 (la comprobación de arriba no es vacía)" do
      manager
      with_tenant(world.organization) { Modules::Enable.call(company:, key: "sample") }
      statuses = module_routes.map do |route|
        process(route[:verb].downcase.to_sym, url_for_route(route[:spec], company), headers: manager.csrf_headers, as: :json)
        response.status
      end

      expect(statuses).to all(satisfy { |status| status != 404 })
    end
  end
end
