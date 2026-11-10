module Modules
  # Lo que devuelven Enable y Disable. `changed` es false cuando la llamada fue una repetición (no hizo nada: ni hook ni evento).
  ActivationResult = Data.define(:key, :company_id, :changed)
end
