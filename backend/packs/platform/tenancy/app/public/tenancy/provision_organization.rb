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
  # - Una sola transacción: si algo falla (incluido un hook), no queda nada a medias.
  # - Los errores previstos se lanzan como Tenancy::ProvisioningFailed (slug reservado o repetido, datos inválidos).
  #   La unicidad del slug la decide la BASE: si dos provisiones compiten, la restricción UNIQUE gana y el perdedor
  #   recibe :slug_taken.
  # - Hooks `after_provision`: otros packs se enganchan SIN modificar este servicio (M0.08: dueño de la organización;
  #   M0.09: módulos por defecto). Corren en orden de registro, dentro de la transacción y dentro del contexto de la
  #   organización nueva. Un hook que lanza revierte TODO y su error se propaga tal cual.
  class ProvisionOrganization
    Result = Data.define(:organization, :company, :branch)

    ORGANIZATION_KEYS = %i[name legal_name country_code].freeze
    COMPANY_KEYS = %i[name slug business_type currency locale].freeze
    BRANCH_KEYS = %i[name time_zone address phone_e164].freeze

    @hooks = [].freeze

    class << self
      def call(organization:, company:, branch:)
        new(organization:, company:, branch:).call
      end

      # Registra un hook (lambda, proc u objeto con #call(result)). Devuelve el hook para poder quitarlo.
      def after_provision(callable = nil, &block)
        hook = callable || block
        raise ArgumentError, "after_provision requiere un objeto que responda a call (o un bloque)" unless hook.respond_to?(:call)

        @hooks = (@hooks + [ hook ]).freeze
        hook
      end

      def remove_after_provision(hook)
        @hooks = (@hooks - [ hook ]).freeze
      end

      def hooks = @hooks
    end

    def initialize(organization:, company:, branch:)
      @organization_attributes = permit(organization, ORGANIZATION_KEYS, :organization)
      @company_attributes = permit(company, COMPANY_KEYS, :company)
      @branch_attributes = permit(branch, BRANCH_KEYS, :branch)
    end

    def call
      result = nil
      FailureTranslator.translating(slug: @company_attributes[:slug]) do
        # requires_new: dentro de una transacción ajena (tests, un job) un fallo hace rollback a un savepoint y deja la
        # conexión utilizable, en vez de abortar la transacción entera.
        ApplicationRecord.transaction(requires_new: true) { result = provision }
      end
      result
    end

    private

    def provision
      organization = Organization.create!(@organization_attributes)
      company, branch = Tenancy.with_context(organization:) do
        company = Company.create!(@company_attributes)
        [ company, Branch.create!(@branch_attributes.merge(company:)) ]
      end
      result = Result.new(organization:, company:, branch:)
      Tenancy.with_context(organization:, company:, branch:) { self.class.hooks.each { |hook| hook.call(result) } }
      result
    end

    def permit(attributes, allowed, section)
      attributes = attributes.to_h.symbolize_keys
      unknown = attributes.keys - allowed
      raise ArgumentError, "Claves no permitidas en #{section}: #{unknown.join(', ')}" if unknown.any?

      attributes
    end
  end
end
