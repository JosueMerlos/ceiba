module Modules
  # Raíz de los errores del pack: se captura todo el dominio de módulos con `rescue Modules::Error`.
  class Error < StandardError; end
end
