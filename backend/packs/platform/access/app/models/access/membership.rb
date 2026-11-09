module Access
  # El usuario `user_id` (global, ADR-0028) tiene el rol `role` en un alcance de la organización: toda ella, una empresa o
  # una sucursal. Tabla TENANT. Las columnas del alcance son explícitas con FKs reales (ADR-0008) y la BASE rechaza las
  # combinaciones incoherentes (chk_memberships_scope); el modelo las valida antes para dar un error legible.
  #
  # Sin asociaciones a user/company/branch: son modelos PRIVADOS de otros packs; se guardan sus ids.
  class Membership < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    belongs_to :role, class_name: "Access::Role"

    enum :scope_level, Role::SCOPE_LEVELS.index_by(&:itself), validate: true

    # El alcance lo da el rol: se denormaliza para que la base pueda expresar el CHECK y la FK compuesta con roles.
    before_validation { self.scope_level = role.scope_level if role }

    validates :user_id, presence: true
    validate :scope_columns_match_level

    private

    def scope_columns_match_level
      case scope_level
      when "organization" then errors.add(:company_id, :present) if company_id || branch_id
      when "company" then errors.add(:company_id, :blank) if company_id.blank?
      when "branch" then errors.add(:branch_id, :blank) if branch_id.blank? || company_id.blank?
      end
      errors.add(:branch_id, :present) if scope_level == "company" && branch_id
    end
  end
end
