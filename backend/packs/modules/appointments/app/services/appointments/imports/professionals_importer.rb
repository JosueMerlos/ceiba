module Appointments
  module Imports
    # Imports a company's professionals (name and whether they take bookings). Branch assignments, services and hours are
    # set up afterwards in the panel.
    class ProfessionalsImporter < CatalogImporter
      COLUMNS = { "nombre" => :display_name, "activo" => :active }.freeze
      REQUIRED = %w[nombre].freeze

      def validate(cells)
        errors = {}
        name = cells["nombre"].presence&.strip
        name_errors(errors, name, max: Professional::MAX_NAME_LENGTH)
        [ { display_name: name, active: boolean(cells["activo"], errors, "activo") }, errors ]
      end

      private

      def existing_records = Professional.where(company_id:).unarchived

      def create(attributes) = Staff::CreateProfessional.call(company_id:, attributes: attributes.transform_keys(&:to_s))
    end
  end
end
