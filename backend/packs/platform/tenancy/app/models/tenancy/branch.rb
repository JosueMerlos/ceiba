module Tenancy
  # A company's branch: time zone, schedules, resources and agenda. Tenant table. Its company must belong to the SAME
  # organization: the composite FK (fk_branches_company) guarantees it and the model translates its violation into a
  # validation error.
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

    # Validation already rejects a company from another organization (it looks it up with the tenant scope). This safety net
    # covers paths that skip it (`save(validate: false)`): the composite FK rejects it and it becomes a validation error
    # instead of a DB exception. It runs in a savepoint so the error does not abort the caller's transaction.
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
