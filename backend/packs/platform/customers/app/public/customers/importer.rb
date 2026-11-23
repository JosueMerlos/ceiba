module Customers
  # Imports a company's customers from a CSV, one person per normalized phone. Consent is never recorded from a file: the
  # consent columns are recognized only to warn that they were ignored, so every imported customer starts without consent.
  #
  # Duplicates (same phone in the company): `skip` leaves the existing customer untouched, archived or not. `update` writes
  # the row's non-empty cells over an active customer, and restores an archived one with the row's data (email and notes
  # the row does not bring are cleared: the number may belong to someone else now).
  class Importer < Imports::Importer
    COLUMNS = { "nombre" => :full_name, "telefono" => :phone_e164, "correo" => :email, "notas" => :notes }.freeze
    REQUIRED = %w[nombre telefono].freeze
    DUPLICATE_MODES = %w[skip update].freeze
    CONSENT_COLUMNS = %w[consentimiento_recordatorios fuente_consentimiento].freeze
    MAX_LENGTHS = { full_name: 200, email: 254, notes: 2000 }.freeze

    def duplicate_column = "telefono"

    def warnings(headers) = headers.intersect?(CONSENT_COLUMNS) ? [ "consent_not_recorded" ] : []

    def validate(cells)
      attributes = {
        full_name: cells["nombre"].presence&.strip,
        phone_e164: Phone.normalize(cells["telefono"], region: Customer.region),
        email: cells["correo"].presence&.strip&.downcase,
        notes: cells["notas"].presence
      }
      [ attributes, errors_of(cells, attributes) ]
    end

    def apply(attributes, mode:)
      existing = Customer.where(company_id:).find_by(phone_e164: attributes[:phone_e164])
      return create(attributes, mode:) unless existing
      return :skipped if mode == "skip"
      return restore(existing, attributes) if existing.archived?

      Update.call(customer: existing, attributes: attributes.compact.except(:phone_e164))
      existing.saved_changes.any? ? :updated : :skipped
    end

    private

    def errors_of(cells, attributes)
      errors = {}
      errors["nombre"] = "blank" if attributes[:full_name].blank?
      errors["telefono"] = cells["telefono"].blank? ? "blank" : "invalid" unless attributes[:phone_e164]
      errors["correo"] = "invalid" if attributes[:email] && !attributes[:email].match?(URI::MailTo::EMAIL_REGEXP)
      MAX_LENGTHS.each do |attribute, max|
        errors[COLUMNS.key(attribute)] ||= "too_long" if attributes[attribute].to_s.length > max
      end
      errors
    end

    # A competitor (another batch row, the booking page) can take the phone between the lookup and the insert: the loser
    # applies the same rule to the winner's row instead of failing.
    def create(attributes, mode:)
      Persist.call(Customer.new(attributes.merge(company_id:)), action: "customer.created")
      :created
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record.errors.of_kind?(:phone_e164, :taken) && Customer.where(company_id:).exists?(phone_e164: attributes[:phone_e164])

      apply(attributes, mode:)
    end

    def restore(customer, attributes)
      Restore.call(customer, full_name: attributes[:full_name], email: attributes[:email], notes: attributes[:notes])
      :restored
    end
  end
end
