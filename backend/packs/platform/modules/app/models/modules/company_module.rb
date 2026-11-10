module Modules
  # A module enabled (or disabled, keeping its data) for a company. Tenant table; private model, used through
  # Modules.enabled?, Modules::Enable/Disable and Modules.settings_for.
  #
  # No association to the company (tenancy's model is private): only its id is stored; the composite FK enforces it.
  class CompanyModule < ApplicationRecord
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :active, -> { where(disabled_at: nil) }

    validates :company_id, :enabled_at, presence: true
    validates :module_key, format: { with: KEY_FORMAT }, uniqueness: { scope: :company_id }

    def active? = disabled_at.nil?
  end
end
