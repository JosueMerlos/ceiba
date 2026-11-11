module Customers
  # The customer of a company with this phone, created if there is none. Meant for flows that must not reveal whether the
  # person already existed (public booking, imports): an existing active customer is returned untouched.
  #
  # An ARCHIVED customer with the same phone comes back to life (a person stays one customer per phone), with the name
  # and email of the call (the previous email and notes are cleared). Two concurrent calls race on the unique index: the loser re-reads the winner's row.
  class FindOrCreate
    def self.call(...) = new(...).call

    def initialize(company_id:, full_name:, phone:, email: nil)
      @company_id = company_id
      @full_name = full_name
      @phone = phone
      @email = email
    end

    def call
      customer = existing
      customer ? revive(customer) : create
    rescue ActiveRecord::RecordInvalid => error
      # A competitor created the phone first (the validation or the unique index saw it): return their row, never a 422.
      raise unless error.record.errors.of_kind?(:phone_e164, :taken)

      revive(existing || raise)
    end

    private

    def existing = Customer.where(company_id: @company_id).with_phone(@phone).first

    def create
      Persist.call(Customer.new(company_id: @company_id, full_name: @full_name, phone_e164: @phone, email: @email), action: "customer.created")
    end

    def revive(customer)
      return customer unless customer.archived?

      Restore.call(customer, full_name: @full_name, email: @email)
    end
  end
end
