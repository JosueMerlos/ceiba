module Modules
  # Shared by Enable and Disable: both run the row change, the module hook and the event in ONE transaction (atomic: if
  # anything fails nothing remains), are idempotent, and require the company to belong to the tenancy context's organization.
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

    # Serializes ALL enables/disables of ONE company until the transaction ends: checking `requires` (read) then writing is not
    # atomic per row, so an Enable of an add-on and a Disable of its base could commit together and leave a module active without
    # what it requires. Other companies are not blocked.
    def lock_company!
      connection = ApplicationRecord.connection
      connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{connection.quote("ceiba.modules.company:#{company.id}")}))")
    end

    # Locked until the transaction ends, so two simultaneous activations serialize.
    def locked_row = CompanyModule.lock.find_by(company_id: company.id, module_key: key)

    def active_keys = CompanyModule.active.where(company_id: company.id).pluck(:module_key)

    # Hooks are strings (the platform does not know module constants), so they are resolved here.
    def run_hook(hook, constant_name, **context)
      return if constant_name.nil?

      callable = constant_name.safe_constantize
      raise Error, "El hook #{hook} del módulo #{key.inspect} apunta a #{constant_name}, que no existe" unless callable.respond_to?(:call)

      callable.call(company:, **context)
    end

    def publish(event_name) = Events.publish(event_name, company_id: company.id, module: key)

    # Audited in the same transaction as the change: if it fails, neither the change, the hook nor the event remains.
    def audit(action, row, before:, after:)
      Audit.record(action:, subject: row, before: { "active" => before }, after: { "active" => after }, metadata: { "module" => key, "company_id" => company.id })
    end

    def result(changed) = ActivationResult.new(key:, company_id: company.id, changed:)
  end
end
