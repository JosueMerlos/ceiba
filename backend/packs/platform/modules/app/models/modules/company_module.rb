module Modules
  # Un módulo ENCENDIDO (o apagado, conservando sus datos) en una empresa. Tabla tenant. Modelo PRIVADO del pack: se usa a
  # través de Modules.enabled?, Modules::Enable/Disable y Modules.settings_for.
  #
  # Sin asociación a la empresa (modelo privado de tenancy): se guarda su id; la FK compuesta la hace cumplir la base.
  class CompanyModule < ApplicationRecord
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :active, -> { where(disabled_at: nil) }

    validates :company_id, :enabled_at, presence: true
    validates :module_key, format: { with: KEY_FORMAT }, uniqueness: { scope: :company_id }

    def active? = disabled_at.nil?
  end
end
