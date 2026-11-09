module Access
  # A qué recursos de la organización activa llega UN permiso: toda la organización, o ciertas empresas y/o sucursales.
  # Lo usan los `Scope` de las policies para filtrar listados con UNA condición, sin preguntar registro por registro:
  #
  #   reach = principal.reach("platform.branch.read")
  #   reach.organization? ? scope : scope.where(company_id: reach.company_ids).or(scope.where(id: reach.branch_ids))
  Reach = Data.define(:organization, :company_ids, :branch_ids) do
    def organization? = organization
    def none? = !organization && company_ids.empty? && branch_ids.empty?
  end
end
