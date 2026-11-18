module Customers
  # Questions other packs may ask about a customer. They receive no contact data; the only personal field that leaves is the
  # full name, for the agenda. Must run inside a tenant context.
  module Lookup
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    module_function

    # Is `id` an active (not archived) customer of the company? An unknown or malformed id, or one from another company, is false.
    def active_id?(id:, company:)
      return false unless id.is_a?(String) && id.match?(UUID)

      Customer.active.exists?(id:, company_id: company.id)
    end

    # { customer id => full name } of the company's customers among `ids`. Archived ones are included: their appointments remain.
    def full_names(ids:, company:)
      return {} if ids.empty?

      Customer.where(id: ids, company_id: company.id).pluck(:id, :full_name).to_h
    end
  end
end
