module Access
  # La organización de la ruta está suspendida: sus miembros no operan bajo ella (403 access.organization_suspended). Quien no
  # es miembro nunca llega a este error: recibe 404 antes, así la suspensión no revela que la organización existe.
  class OrganizationSuspended < Error; end
end
