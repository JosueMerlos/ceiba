module Api
  # Base de todos los controladores de la API JSON (/api/v1/...). Los controladores de cada pack heredan de aquí
  # (`Api::V1::<Pack>::XController < Api::BaseController`) y obtienen los rescates problem+json y, más adelante,
  # la autenticación (M0.07). Las sondas /api/health y /api/ready NO heredan de aquí: son infraestructura.
  class BaseController < ApplicationController
    include ErrorHandling
    include Paginated
  end
end
