module Appointments
  module Imports
    # Imports a company's services. Prices are read literally: an integer or a decimal with "." or "," and up to two
    # decimals. A thousands separator ("1.500,00", "1,500.00", "1.500") is rejected instead of guessed, because the same
    # text means 1500 in one locale and 1.5 in another. The currency, when given, must be the company's.
    class ServicesImporter < CatalogImporter
      COLUMNS = { "nombre" => :name, "duracion_minutos" => :duration_minutes, "precio" => :price_minor, "moneda" => :currency,
                  "buffer_antes_minutos" => :buffer_before_minutes, "buffer_despues_minutos" => :buffer_after_minutes,
                  "activo" => :active }.freeze
      REQUIRED = %w[nombre duracion_minutos precio].freeze
      PRICE = /\A(\d+)(?:[.,](\d{1,2}))?\z/
      THOUSANDS = /\A\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?\z/
      MINUTES = (0..Service::MAX_MINUTES)

      def validate(cells)
        errors = {}
        name = cells["nombre"].presence&.strip
        name_errors(errors, name, max: Service::MAX_NAME_LENGTH)
        attributes = {
          name:,
          duration_minutes: integer(cells["duracion_minutos"], errors, "duracion_minutos", range: (1..Service::MAX_MINUTES)),
          price_minor: price(cells["precio"], errors),
          currency: currency(cells["moneda"], errors),
          buffer_before_minutes: integer(cells["buffer_antes_minutos"], errors, "buffer_antes_minutos", range: MINUTES, default: 0),
          buffer_after_minutes: integer(cells["buffer_despues_minutos"], errors, "buffer_despues_minutos", range: MINUTES, default: 0),
          active: boolean(cells["activo"], errors, "activo")
        }
        [ attributes, errors ]
      end

      private

      def existing_records = Service.where(company_id:).unarchived

      def create(attributes) = Catalog::CreateService.call(company_id:, attributes: attributes.transform_keys(&:to_s))

      def price(value, errors)
        minor = price_minor(value.to_s.strip)
        return minor if minor.is_a?(Integer)

        errors["precio"] = minor
        nil
      end

      # The amount in minor units, or the error code.
      def price_minor(text)
        return "blank" if text.empty?
        return "thousands_separator" if text.match?(THOUSANDS)

        match = PRICE.match(text)
        return "invalid" unless match

        minor = (match[1].to_i * 100) + match[2].to_s.ljust(2, "0").to_i
        minor <= Service::MAX_PRICE_MINOR ? minor : "invalid"
      end

      def currency(value, errors)
        return company_currency if value.blank?

        errors["moneda"] = "mismatch" unless value.strip.upcase == company_currency
        company_currency
      end

      # Read once per importer (one per batch or chunk), not once per row.
      def company_currency = @company_currency ||= Tenancy::Directory.companies.find_by(id: company_id)&.currency
    end
  end
end
