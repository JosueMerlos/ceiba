module Api
  module Pagination
    # Base de los errores de paginación: todos son 400 (el cliente mandó un parámetro inválido).
    class Error < StandardError; end
  end
end
