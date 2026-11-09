module Api
  # Base de los serializers de la API: `class Tenancy::OrganizationSerializer < Api::Serializer`. Un serializer por
  # representación (resumen, detalle...), nunca un serializer con condicionales. Lo que no se lista NO sale: añadir
  # un campo es una decisión visible en el diff Y en el contrato (rswag valida con esquema estricto y CI regenera
  # openapi/v1.yaml; ver docs/architecture/07-api-contract.md).
  class Serializer
    include Alba::Resource
  end
end
