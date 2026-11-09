module Api
  # Base de todos los controladores de la API JSON (/api/v1/...). Los controladores de cada pack heredan de aquí
  # (`Api::V1::<Pack>::XController < Api::BaseController`) y obtienen los rescates problem+json y la autenticación
  # OBLIGATORIA por defecto (M0.07, deny by default; ver Api::Authentication). Las sondas /api/health y /api/ready NO
  # heredan de aquí: son infraestructura.
  class BaseController < ApplicationController
    include ErrorHandling
    include RequestMetadata
    include Authentication
    include Access::Authorization
    include Paginated
  end
end
