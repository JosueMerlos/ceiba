module Appointments
  # A service a company offers. TENANT table scoped to the COMPANY; only `company_id` is stored (no association to
  # Tenancy::Company, a private model of another pack). Money is an integer in minor units (`price_minor`) plus a currency,
  # which must be the company's. Never destroyed: it is archived (`archived_at`) so history can keep referencing it.
  class Service < ApplicationRecord
    CURRENCIES = %w[NIO USD].freeze
    # A service never takes longer than a day; the cap also keeps the value inside the integer column.
    MAX_MINUTES = 1440
    # Display order is a small integer; the cap only keeps garbage out of the column.
    MAX_POSITION = 10_000
    # Largest integer a JavaScript number holds exactly (Number.MAX_SAFE_INTEGER): the generated TS client never loses precision.
    MAX_PRICE_MINOR = (2**53) - 1
    # What a client may write; the audit trail records these plus `archived_at`.
    EDITABLE = %w[name duration_minutes buffer_before_minutes buffer_after_minutes price_minor currency active position].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    before_validation :normalize_fields
    before_validation :default_currency

    validates :name, presence: true, length: { maximum: 200 }
    validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_MINUTES }
    validates :buffer_before_minutes, :buffer_after_minutes,
              numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_MINUTES }
    validates :price_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_PRICE_MINOR }
    validates :currency, inclusion: { in: CURRENCIES }
    validates :active, inclusion: { in: [ true, false ] }
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_POSITION }
    validate :company_exists
    validate :currency_matches_company, if: -> { company && (new_record? || currency_changed?) }

    # What management lists: everything not archived, paused services included.
    scope :unarchived, -> { where(archived_at: nil) }
    # What can be offered for booking: not archived and not paused.
    scope :active, -> { unarchived.where(active: true) }

    # The records of `ids` in the order asked for (a repeated id stays repeated, so a caller can report it); one that is not in
    # the scope is a 404.
    def self.in_order(ids)
      found = where(id: ids.uniq).index_by(&:id)
      ids.map { found.fetch(it) { raise ActiveRecord::RecordNotFound, "No se encontró el recurso" } }
    end

    def archived? = !archived_at.nil?

    # The company's currency, read through the public directory (nil outside the active organization).
    def company
      return if company_id.blank?

      @company = nil if @company && @company.id != company_id
      @company ||= Tenancy::Directory.companies.find_by(id: company_id)
    end

    private

    def normalize_fields
      self.name = name.strip if name
    end

    def default_currency
      self.currency = company.currency if currency.blank? && company
    end

    def company_exists
      errors.add(:company_id, :invalid) if company_id.blank? || company.nil?
    end

    def currency_matches_company
      errors.add(:currency, :mismatch) if currency.present? && currency != company.currency
    end
  end
end
