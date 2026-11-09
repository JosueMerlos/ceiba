module Identity
  # Mutación cuyo `Origin` (o `Referer`) no es el origen propio. La API responde 403.
  class ForbiddenOrigin < Error; end
end
