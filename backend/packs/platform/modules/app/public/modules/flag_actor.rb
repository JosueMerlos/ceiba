module Modules
  # El actor de Flipper para una organización: Flipper identifica a un actor con `flipper_id`. Se usa un value object con el id (y no el
  # modelo Tenancy::Organization, privado de otro pack) para activar un flag por organización:
  #
  #   Flipper.enable_actor(:nueva_funcion, Modules::FlagActor.new(organization.id))
  #   Modules.flag_enabled?(:nueva_funcion, organization:)
  FlagActor = Data.define(:id) do
    def flipper_id = "Organization;#{id}"
  end
end
