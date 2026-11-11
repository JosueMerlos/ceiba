module Customers
  # A person a company serves. TENANT table scoped to the COMPANY: the same phone in two companies of one group is two
  # customers. Only `company_id` is stored (no association to Tenancy::Company, a private model of another pack).
  #
  # phone_e164 and email are deterministic ciphertext (searchable, and what the unique index compares); notes is
  # randomized. full_name stays in the clear to allow prefix search.
  class Customer < ApplicationRecord
    # What staff may write; the audit trail records these plus `archived_at`.
    EDITABLE = %w[full_name phone_e164 email notes].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    encrypts :phone_e164, deterministic: true
    encrypts :email, deterministic: true, downcase: true
    encrypts :notes

    before_validation :normalize_fields

    validates :company_id, presence: true
    validates :full_name, presence: true, length: { maximum: 200 }
    validate :phone_is_a_real_number, if: :phone_needs_checking?
    validates :phone_e164, uniqueness: { scope: :company_id }, if: -> { phone_e164_changed? || company_id_changed? }, unless: -> { errors.key?(:phone_e164) }
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }, allow_nil: true
    validates :notes, length: { maximum: 2000 }

    scope :active, -> { where(archived_at: nil) }

    # Prefix search, case-insensitive; the pattern characters of the input are escaped so "%" matches nothing special.
    def self.name_prefix(query)
      where("lower(full_name) LIKE lower(?)", "#{sanitize_sql_like(query.to_s)}%")
    end

    # Looks the customer up by a phone in any format. A value that is not a phone matches nothing.
    def self.with_phone(raw)
      normalized = Phone.normalize(raw, region:)
      normalized ? where(phone_e164: normalized) : none
    end

    # The country numbers without an international prefix are assumed to belong to: the organization's.
    def self.region = Current.context.organization.country_code

    def archived? = !archived_at.nil?

    private

    # Same rule as `with_phone`: a phone is valid only when it normalizes, so what is stored is always what a lookup finds.
    # A stored number is not revalidated on unrelated saves: a phone metadata update must not block archiving or notes.
    def phone_needs_checking? = new_record? || phone_e164_changed?

    def phone_is_a_real_number
      errors.add(:phone_e164, :invalid) unless Phone.normalize(phone_e164, region: self.class.region)
    end

    def normalize_fields
      self.full_name = full_name.strip if full_name
      self.email = email.strip.presence if email
      self.notes = notes.presence if notes
      return unless phone_needs_checking?

      normalized = Phone.normalize(phone_e164, region: self.class.region)
      self.phone_e164 = normalized if normalized
    end
  end
end
