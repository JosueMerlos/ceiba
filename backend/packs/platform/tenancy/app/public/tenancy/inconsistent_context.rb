module Tenancy
  # El contexto pedido mezcla entidades que no encajan (una empresa de otra organización, una sucursal que no es de
  # la empresa indicada...). Se lanza ANTES de tocar el tenant ni la base de datos.
  class InconsistentContext < Error; end
end
