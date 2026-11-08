module Tenancy
  # La organización es el TENANT (ADR-0003): la frontera dura entre clientes. Es la raíz, no lleva organization_id
  # ni acts_as_tenant, así que se puede consultar sin contexto (lo hace el servicio de provisión y el back-office).
  class Organization < ApplicationRecord
    enum :status, { active: "active", suspended: "suspended" }, default: "active", validate: true

    # Sus empresas son datos tenant: recorrerlas exige un contexto activo (NoTenantSet si no lo hay). Sin `dependent`
    # a propósito: borrar una organización es un offboarding explícito y la FK (restrict) lo impide mientras tenga datos.
    has_many :companies, class_name: "Tenancy::Company", inverse_of: :organization # rubocop:disable Rails/HasManyOrHasOneDependent

    validates :name, presence: true
    validates :country_code, format: { with: /\A[A-Z]{2}\z/ }
  end
end
