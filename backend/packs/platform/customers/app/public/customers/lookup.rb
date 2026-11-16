module Customers
  # Questions other packs may ask about a customer without receiving any of its data. Must run inside a tenant context.
  module Lookup
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    module_function

    # Is `id` an active (not archived) customer of the company? An unknown or malformed id, or one from another company, is false.
    def active_id?(id:, company:)
      return false unless id.is_a?(String) && id.match?(UUID)

      Customer.active.exists?(id:, company_id: company.id)
    end
  end
end
