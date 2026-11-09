module Tenancy
  # El ÚNICO camino para crear una organización con su primera empresa y su primera sucursal (seeds, consola,
  # back-office M4.01, tests y el futuro auto-registro).
  #
  #   result = Tenancy::ProvisionOrganization.call(
  #     organization: { name:, legal_name: },
  #     company:      { name:, slug:, business_type:, currency: },
  #     branch:       { name:, time_zone: }
  #   )
  #   result.organization / result.company / result.branch
  #
  # `extras:` (opcional) lleva a los hooks datos que este servicio NO interpreta, p. ej. el dueño que access convierte en un
  # membership `org_owner` (M0.08) o el plan que fija los módulos por defecto (M0.09). Llegan en `result.extras`, congelados.
  # Cada hook valida los suyos y decide si la ausencia de un dato es un error. Sin `extras:` todo funciona como antes:
  #
  #   Tenancy::ProvisionOrganization.call(organization:, company:, branch:, extras: { owner: Identity::ProvisionUser.call(...) })
  #
  # - Una sola transacción: si algo falla (incluido un hook), no queda nada a medias.
  # - Los errores previstos se lanzan como Tenancy::ProvisioningFailed (slug reservado o repetido, datos inválidos).
  #   La unicidad del slug la decide la BASE: si dos provisiones compiten, la restricción UNIQUE gana y el perdedor
  #   recibe :slug_taken.
  # - Hooks `after_provision`: otros packs se enganchan SIN modificar este servicio (M0.08: dueño de la organización;
  #   M0.09: módulos por defecto). Corren en orden de registro, dentro de la transacción y dentro del contexto de la
  #   organización nueva. Un hook que lanza revierte TODO y su error se propaga tal cual.
  class ProvisionOrganization
    Result = Data.define(:organization, :company, :branch, :extras) do
      def initialize(organization:, company:, branch:, extras: {})
        super(organization:, company:, branch:, extras: extras.dup.freeze)
      end
    end

    # El registro de hooks vive en la configuración de la aplicación y NO en la clase: en desarrollo la clase se
    # recarga y un ivar de clase perdería los hooks. Cada hook puede llevar una `key`: registrar otro con la misma
    # clave lo REEMPLAZA, así un `config.to_prepare { ProvisionOrganization.after_provision(Hook, key: :x) }` es
    # idempotente aunque corra en cada recarga (y los callables recargables no quedan obsoletos).
    STORE = Rails.application.config.x.tenancy

    class << self
      def call(organization:, company:, branch:, extras: {})
        new(organization:, company:, branch:, extras:).call
      end

      # Registra un hook (lambda, proc u objeto con #call(result)). Devuelve el hook para poder quitarlo.
      def after_provision(callable = nil, key: nil, &block)
        hook = callable || block
        raise ArgumentError, "after_provision requiere un objeto que responda a call (o un bloque)" unless hook.respond_to?(:call)

        update_hooks do |entries|
          index = key && entries.index { |entry| entry.first == key }
          index ? entries.dup.tap { |copy| copy[index] = [ key, hook ] } : entries + [ [ key, hook ] ]
        end
        hook
      end

      def remove_after_provision(hook)
        update_hooks { |entries| entries.reject { |_key, registered| registered.equal?(hook) } }
      end

      def hooks = (STORE.after_provision_hooks || []).map(&:last)

      private

      def update_hooks
        lock.synchronize { STORE.after_provision_hooks = yield(STORE.after_provision_hooks || []).freeze }
      end

      def lock = STORE.after_provision_lock ||= Mutex.new
    end

    def initialize(organization:, company:, branch:, extras: {})
      raise ArgumentError, "extras debe ser un Hash (recibió #{extras.class})" unless extras.is_a?(Hash)

      @extras = extras
      @organization_attributes = AllowedAttributes.permit(organization, AllowedAttributes::ORGANIZATION, :organization)
      @company_attributes = AllowedAttributes.permit(company, AllowedAttributes::COMPANY, :company)
      @branch_attributes = AllowedAttributes.permit(branch, AllowedAttributes::BRANCH, :branch)
    end

    def call
      result = nil
      # requires_new: dentro de una transacción ajena (tests, un job) un fallo hace rollback a un savepoint y deja la
      # conexión utilizable, en vez de abortar la transacción entera.
      ApplicationRecord.transaction(requires_new: true) do
        result = FailureTranslator.translating(slug: @company_attributes[:slug]) { create_records }.with(extras: @extras)
        # Los hooks corren en la MISMA transacción pero FUERA del traductor: su error se propaga tal cual (y revierte todo),
        # no se disfraza de ProvisioningFailed.
        run_hooks(result)
      end
      result
    end

    private

    def create_records
      organization = Organization.create!(@organization_attributes)
      company, branch = Tenancy.with_context(organization:) do
        company = Company.create!(@company_attributes)
        [ company, Branch.create!(@branch_attributes.merge(company:)) ]
      end
      Result.new(organization:, company:, branch:)
    end

    def run_hooks(result)
      Tenancy.with_context(organization: result.organization, company: result.company, branch: result.branch) do
        self.class.hooks.each { |hook| hook.call(result) }
      end
    end
  end
end
