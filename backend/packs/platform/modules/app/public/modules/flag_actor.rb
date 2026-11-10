module Modules
  # Flipper actor for an organization (Flipper identifies actors by `flipper_id`). A value object with the id is used instead
  # of Tenancy::Organization, which is private to another pack:
  #
  #   Flipper.enable_actor(:nueva_funcion, Modules::FlagActor.new(organization.id))
  #   Modules.flag_enabled?(:nueva_funcion, organization:)
  FlagActor = Data.define(:id) do
    def flipper_id = "Organization;#{id}"
  end
end
