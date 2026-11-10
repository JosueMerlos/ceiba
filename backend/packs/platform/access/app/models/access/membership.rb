module Access
  # The (global) user `user_id` has the role `role` at a scope of the organization: all of it, a company or a branch.
  # TENANT table. Scope columns are explicit with real FKs and the DATABASE rejects inconsistent combinations
  # (chk_memberships_scope); the model validates them first to give a readable error.
  #
  # No associations to user/company/branch: they are PRIVATE models of other packs, so only their ids are stored.
  class Membership < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    belongs_to :role, class_name: "Access::Role"

    enum :scope_level, Role::SCOPE_LEVELS.index_by(&:itself), validate: true

    # The role determines the scope; it is denormalized so the database can express the CHECK and the composite FK to roles.
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
