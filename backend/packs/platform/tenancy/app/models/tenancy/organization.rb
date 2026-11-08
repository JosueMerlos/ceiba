module Tenancy
  # La organización es el TENANT (ADR-0003): la frontera dura entre clientes. Es la raíz, no lleva organization_id
  # ni acts_as_tenant, así que se puede consultar sin contexto (lo hace el servicio de provisión y el back-office).
  class Organization < ApplicationRecord
    enum :status, { active: "active", suspended: "suspended" }, default: "active", validate: true

    # SIN `has_many :companies`, a propósito: una asociación cuya condición es `organization_id = <esta organización>`
    # REEMPLAZA el scope del tenant, así que desde el contexto A `Organization.find(b.id).companies` devolvería las
    # empresas de B. Las empresas se consultan dentro de un tenant (`Tenancy.with_context(...) { Company.all }`). Lo
    # vigila TenantIsolation.association_violations (spec/platform/tenancy/isolation_spec.rb).
    # Borrar una organización con datos lo impide la FK (restrict), no el modelo.

    validates :name, presence: true
    validates :country_code, format: { with: /\A[A-Z]{2}\z/ }
  end
end
