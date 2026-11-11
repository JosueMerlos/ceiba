module Appointments
  # Shared by the rows that belong to a professional or a resource (weekly schedules, absences): the owner is one nullable
  # id column per kind (never polymorphic, so each can carry a composite foreign key) and `owner_type` says which one is set.
  # The predicates let policies and services ask the kind without comparing strings.
  module OwnerScoped
    extend ActiveSupport::Concern

    included do
      # Optional: a missing owner is reported as a field error by the including model, not as "must exist".
      belongs_to :professional, class_name: "Appointments::Professional", optional: true
      belongs_to :resource, class_name: "Appointments::Resource", optional: true

      scope :owned_by, ->(owner) { where(owner_attributes(owner)) }
    end

    class_methods do
      # The owner columns that identify the rows of an owner: a professional, a resource, or (anything else) the branch itself.
      def owner_attributes(owner)
        case owner
        when Professional then { owner_type: "professional", professional_id: owner.id }
        when Resource then { owner_type: "resource", resource_id: owner.id }
        else { owner_type: "branch" }
        end
      end
    end

    def professional_owner? = owner_type == "professional"
    def resource_owner? = owner_type == "resource"
    def branch_owner? = owner_type == "branch"

    private

    # Mirrors the CHECK of the table: exactly the column of the owner kind is set.
    def owner_columns_match_type
      expected = { "branch" => [ nil, nil ], "professional" => [ professional_id, nil ], "resource" => [ nil, resource_id ] }[owner_type]
      return if expected.nil? || (professional_id.nil? == expected[0].nil? && resource_id.nil? == expected[1].nil?)

      errors.add(:base, :invalid)
    end

    # The id column of the owner kind, as a field error when the row's owner is missing or from another company.
    def owner_in_company
      errors.add(:professional_id, :invalid) if professional_owner? && professional&.company_id != company_id
      errors.add(:resource_id, :invalid) if resource_owner? && resource&.company_id != company_id
    end
  end
end
