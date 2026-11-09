module Modules
  # Lo común de Enable y Disable (docs/architecture/05-module-system.md, "Activación por empresa"): ambos corren en UNA
  # transacción con el cambio de la fila, el hook del módulo y el evento (atómicos: si algo falla no queda nada), son idempotentes
  # y exigen que la empresa sea de la organización del contexto de tenancy.
  class Activation
    def self.call(company:, key:) = new(company:, key:).call

    def initialize(company:, key:)
      @company = company
      @manifest = Modules.registry.fetch(key)
      ensure_company_in_context!
    end

    private

    attr_reader :company, :manifest

    def key = manifest.key

    def ensure_company_in_context!
      tenant = ActsAsTenant.current_tenant
      raise Error, "#{self.class.name} exige Tenancy.with_context de la organización de la empresa" if tenant.nil?
      return if company.organization_id == tenant.id

      raise Error, "La empresa #{company.id} no pertenece a la organización del contexto (#{tenant.id})"
    end

    # Fila de (empresa, módulo) bloqueada hasta el fin de la transacción: dos activaciones simultáneas se serializan.
    def locked_row = CompanyModule.lock.find_by(company_id: company.id, module_key: key)

    def active_keys = CompanyModule.active.where(company_id: company.id).pluck(:module_key)

    # `on_enable`/`on_disable` son cadenas (la plataforma no conoce las constantes de los módulos): se resuelven aquí.
    def run_hook(hook, constant_name)
      return if constant_name.nil?

      callable = constant_name.safe_constantize
      raise Error, "El hook #{hook} del módulo #{key.inspect} apunta a #{constant_name}, que no existe" unless callable.respond_to?(:call)

      callable.call(company:)
    end

    def publish(event_name) = Events.publish(event_name, company_id: company.id, module: key)

    # TODO(M0.11): auditar la activación/desactivación con Audit.record (actor, empresa, módulo) en esta misma transacción. El
    # punto de conexión es este método: Enable y Disable lo llaman dentro de la transacción, después del hook y del evento.
    def audit(_action); end

    def result(changed) = ActivationResult.new(key:, company_id: company.id, changed:)
  end
end
