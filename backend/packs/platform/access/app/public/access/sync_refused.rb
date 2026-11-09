module Access
  # Access.sync! se negó a tocar la base: el registro está vacío o retiraría permisos/concesiones sin autorización. No cambió nada.
  class SyncRefused < Error; end
end
