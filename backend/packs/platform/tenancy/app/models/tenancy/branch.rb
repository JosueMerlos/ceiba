module Tenancy
  # Sucursal: zona horaria, horarios, recursos y agenda de una empresa. Tabla tenant. Su empresa debe ser de la MISMA
  # organización: lo garantiza la FK compuesta de la base (fk_branches_company) y el modelo traduce su violación
  # a un error de validación.
  class Branch < ApplicationRecord
    COMPANY_FOREIGN_KEY = "fk_branches_company".freeze
    TIME_ZONES = TZInfo::Timezone.all_identifiers.to_set.freeze
    PHONE_E164 = /\A\+[1-9][0-9]{6,14}\z/

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    enum :status, { active: "active", inactive: "inactive" }, default: "active", validate: true

    belongs_to :company, class_name: "Tenancy::Company", inverse_of: :branches

    validates :name, presence: true
    validates :time_zone, inclusion: { in: TIME_ZONES, message: :invalid_time_zone }
    validates :phone_e164, format: { with: PHONE_E164 }, allow_nil: true

    private

    # La validación del modelo ya rechaza una empresa de otra organización (la busca con el scope del tenant). Esta red
    # cubre lo que se salta ese camino (`save(validate: false)`): la FK compuesta de la base lo rechaza y aquí se
    # convierte en un error de validación en vez de una excepción de BD. El intento corre en un savepoint para que el
    # error no aborte la transacción del llamador.
    def create_or_update(**)
      self.class.transaction(requires_new: true) { super }
    rescue ActiveRecord::InvalidForeignKey => error
      raise unless violated_constraint(error) == COMPANY_FOREIGN_KEY

      errors.add(:company, :different_organization)
      raise ActiveRecord::RecordInvalid, self
    end

    def violated_constraint(error)
      error.cause&.result&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME)
    end
  end
end
