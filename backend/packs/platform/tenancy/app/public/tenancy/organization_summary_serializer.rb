module Tenancy
  # Resumen de una organización para el SELECTOR DE CONTEXTO (GET /organizations, ADR-0028): solo lo necesario para elegir
  # (id, nombre, estado). La razón social, el país y las fechas se piden con el detalle, que exige permiso. Coincide con
  # components.schemas.OrganizationSummary.
  class OrganizationSummarySerializer < Api::Serializer
    attributes :id, :name, :status
  end
end
