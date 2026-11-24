module Appointments
  module Imports
    # Shared rules of the catalog importers. A catalog row only creates: a name already used by a non-archived record of
    # the company (compared trimmed, case-insensitively) is skipped, never updated, so an import cannot change a price or
    # merge two people who share a name. Inside this namespace `Imports` is Appointments::Imports: the platform pack is
    # always written `::Imports`.
    class CatalogImporter < ::Imports::Importer
      TRUE_VALUES = %w[si sí s true 1 yes activo activa].freeze
      FALSE_VALUES = %w[no n false 0 inactivo inactiva].freeze
      INTEGER = /\A\d+\z/

      def duplicate_column = "nombre"

      def duplicate_key(attributes) = normalize_name(attributes[columns.fetch("nombre")])

      def apply(attributes, mode:)
        key = duplicate_key(attributes)
        return :skipped if existing_names.include?(key)

        create(attributes)
        existing_names << key
        :created
      end

      private

      def existing_names = @existing_names ||= existing_records.pluck(columns.fetch("nombre")).to_set { normalize_name(it) }

      def normalize_name(value) = value.to_s.strip.squeeze(" ").downcase

      def name_errors(errors, name, max:)
        errors["nombre"] = "blank" if name.blank?
        errors["nombre"] = "too_long" if name.to_s.length > max
      end

      # Blank is the default; anything else that is not a known yes/no is an error, never a guess.
      def boolean(value, errors, column, default: true)
        return default if value.blank?

        normalized = value.strip.downcase
        return true if TRUE_VALUES.include?(normalized)
        return false if FALSE_VALUES.include?(normalized)

        errors[column] = "invalid"
        nil
      end

      def integer(value, errors, column, range:, default: nil)
        return default.tap { errors[column] = "blank" if default.nil? } if value.blank?

        number = value.strip.match?(INTEGER) ? value.strip.to_i : nil
        return number if number && range.cover?(number)

        errors[column] = "invalid"
        nil
      end
    end
  end
end
