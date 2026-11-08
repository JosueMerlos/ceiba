module Tenancy
  # Traduce los fallos de persistencia (validaciones y la restricción UNIQUE del slug) a Tenancy::ProvisioningFailed,
  # el error de dominio que ven quienes llaman a la API pública. Privado del pack.
  module FailureTranslator
    SLUG_CONSTRAINT = "uq_companies_slug".freeze

    module_function

    def from_record(record)
      section = section_of(record)
      details = { section => record.errors.to_hash }
      case slug_error(record, section)
      when :exclusion then ProvisioningFailed.new(:slug_reserved, I18n.t("tenancy.provisioning_failed.slug_reserved", slug: record.slug), details:)
      when :taken then slug_taken(record.slug)
      else ProvisioningFailed.new(:invalid, I18n.t("tenancy.provisioning_failed.invalid", errors: full_messages(record, section)), details:)
      end
    end

    def slug_taken(slug)
      message = I18n.t("tenancy.provisioning_failed.slug_taken", slug:)
      ProvisioningFailed.new(:slug_taken, message, details: { company: { slug: [ message ] } })
    end

    # Nombre de la restricción de BD violada por un ActiveRecord::StatementInvalid (nil si no se puede saber).
    def violated_constraint(error)
      error.cause&.result&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
    end

    # Ejecuta el bloque y convierte los fallos previstos en ProvisioningFailed. `slug:` es el slug pedido, para el caso
    # de la carrera en que gana la restricción UNIQUE de la base.
    def translating(slug: nil)
      yield
    rescue ActiveRecord::RecordInvalid => error
      raise from_record(error.record)
    rescue ActiveRecord::RecordNotUnique => error
      raise unless violated_constraint(error) == SLUG_CONSTRAINT

      raise slug_taken(Company.normalize_value_for(:slug, slug.to_s))
    end

    def section_of(record)
      case record
      when Organization then :organization
      when Company then :company
      when Branch then :branch
      else raise ArgumentError, "FailureTranslator no sabe traducir #{record.class.name}"
      end
    end

    def slug_error(record, section)
      return unless section == :company

      (record.errors.details[:slug].pluck(:error) & %i[exclusion taken]).first
    end

    def full_messages(record, section)
      prefix = I18n.t("tenancy.provisioning_failed.sections.#{section}")
      record.errors.full_messages.map { |message| "#{prefix}: #{message}" }.join("; ")
    end
  end
end
