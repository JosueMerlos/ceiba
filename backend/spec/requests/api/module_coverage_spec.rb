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

  # ¿Corre el gate en TODAS las acciones? Un before_action con `only:`/`except:`/`if:` lleva condiciones; uno saltado con
  # skip_before_action (sin opciones) desaparece, y con `only:` gana una condición `unless`. Exigimos el callback sin condiciones.
  def gate_everywhere?(klass)
    callback = klass._process_action_callbacks.find { |candidate| candidate.kind == :before && candidate.filter == :ensure_required_module_enabled! }
    callback.present? && callback.instance_variable_get(:@if).blank? && callback.instance_variable_get(:@unless).blank?
  end

  # URL con ids REALES: un id desconocido (o la sucursal de otra empresa) da 404 en el resolvedor de rutas o en la acción, ANTES o
  # aparte del gate, y la comprobación no probaría nada. :branch_id es una sucursal real de la empresa; los demás parámetros
  # (:id, ...) los fabrica el módulo con ModuleCoverageFactories (falla explícito si falta).
  def url_for_route(route, company)
    route[:spec].gsub(/:(\w+)/) do
      case (param = Regexp.last_match(1).to_sym)
      when :organization_id then company.organization_id
      when :company_id then company.id
      when :branch_id then world.branch_a1.id
      else ModuleCoverageFactories.build(route[:module], param, company:, branch: world.branch_a1)
      end
    end
  end

  let(:world) { build_access_world }
  let(:company) { world.company_a }
  let(:manager) { sign_in(user_with_role("company_manager", world, company:)) }

  describe "estática" do
    it "todo controlador de un pack de módulos declara requires_module con la key de su propio pack" do
      wrong = module_controllers.reject { |klass, key| klass.respond_to?(:required_module) && klass.required_module == key }

      expect(wrong.keys).to be_empty, "controladores sin `requires_module :<key>` de su pack: #{wrong.keys.map(&:name).join(', ')}"
    end

    it "el gate (ensure_required_module_enabled!) está en los callbacks efectivos de CADA acción: sin skip, ni only ni except" do
      leaking = module_controllers.keys.select { |klass| !gate_everywhere?(klass) }

      expect(leaking).to be_empty, "el gate no corre en todas las acciones de: #{leaking.map(&:name).join(', ')}"
    end

    it "la comprobación detecta un controlador que no lo declara (no es vacía)" do
      leaky = Class.new(Api::BaseController)
      declared = Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :sample }

      expect([ leaky, declared ].reject { |klass| klass.respond_to?(:required_module) && klass.required_module == "sample" }).to eq([ leaky ])
    end

    it "detecta un controlador que declara el módulo pero se salta el gate (sonda C1)" do
      skipping = Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :sample; skip_before_action :ensure_required_module_enabled! }
      partial = Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :sample; skip_before_action :ensure_required_module_enabled!, only: :show }
      only_on_some = Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :sample }

      expect([ gate_everywhere?(skipping), gate_everywhere?(partial), gate_everywhere?(only_on_some) ]).to eq([ false, false, true ])
    end
  end

  describe "dinámica" do
    it "encuentra las rutas con módulo (incluida la de sample)" do
      expect(module_routes.pluck(:module)).to include("sample")
    end

    # Un id desconocido da 404 POR SÍ SOLO en una ruta de miembro (:id): el status no prueba nada. Lo que se comprueba es que el
    # GATE emitió el 404: Modules::RequiresModule instrumenta "denied.requires_module" cada vez que lo deniega.
    def denials_during
      denials = []
      subscriber = ->(*, payload) { denials << payload }
      ActiveSupport::Notifications.subscribed(subscriber, "denied.requires_module") { yield }
      denials
    end

    it "con el módulo inactivo, TODAS responden 404 problem+json y el 404 lo emite el gate (no un id desconocido)" do
      manager
      results = module_routes.map do |route|
        denials = denials_during { process(route[:verb].downcase.to_sym, url_for_route(route, company), headers: manager.csrf_headers, as: :json) }
        [ route[:spec], response.status, response.parsed_body["code"], denials.pluck(:module) ]
      end

      expect(results).to all(satisfy { |spec, status, code, denied| status == 404 && code == "resource.not_found" && denied == [ module_routes.find { |r| r[:spec] == spec }[:module] ] })
    end

    it "cubre rutas con :id y :branch_id (con ids reales)" do
      specs = module_routes.pluck(:spec)

      expect(specs).to include(a_string_including("/branches/:branch_id/"), a_string_including("/things/:id"))
    end

    it "falla explícitamente si un módulo no registra cómo fabricar el recurso de un parámetro" do
      expect { ModuleCoverageFactories.build("sample", :slug, company:, branch: world.branch_a1) }
        .to raise_error(ModuleCoverageFactories::Missing, /registra un fabricante para :slug de sample/)
    end

    it "con el módulo activo dejan de ser 404 (la comprobación de arriba no es vacía)" do
      manager
      with_tenant(world.organization) { Modules::Enable.call(company:, key: "sample") }
      statuses = module_routes.map do |route|
        process(route[:verb].downcase.to_sym, url_for_route(route, company), headers: manager.csrf_headers, as: :json)
        response.status
      end

      expect(statuses).to all(satisfy { |status| status != 404 })
    end
  end
end
