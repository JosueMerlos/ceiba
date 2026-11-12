module Appointments
  module Availability
    # Who the visit is with: one professional, or whoever is free (any). Resolved once at the boundary so the use case never
    # compares a symbol with a record.
    ProfessionalChoice = Data.define(:professional) do
      def self.any = new(professional: nil)

      def self.of(professional) = new(professional:)

      # `id` is a parsed query value (a UUID or :any); `within` is the scope a concrete professional is searched in (404 when it is
      # not there).
      def self.resolve(id, within:) = id == :any ? any : of(within.find(id))

      def any? = professional.nil?

      # The records the request names, for the checks that need them.
      def named = any? ? [] : [ professional ]

      def cache_token = any? ? "any" : professional.id
    end
  end
end
