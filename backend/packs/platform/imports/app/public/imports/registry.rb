module Imports
  # Which packs import which kind of file. The imports pack knows none of them: each owner registers, from
  # `config.to_prepare`, its importer and the policy that authorizes it (by class NAME, resolved at call time so code
  # reloading keeps working). `module_key` names the module that must be active in the company, or nil for platform data.
  #
  #   Rails.application.config.to_prepare do
  #     Imports::Registry.register("customers", importer: "Customers::Importer", policy: "Customers::ImportPolicy")
  #   end
  module Registry
    Entry = Data.define(:kind, :importer, :policy, :module_key) do
      def importer_class = importer.constantize
      def importer_for(company_id:) = importer_class.new(company_id:)
      def policy_class = policy.constantize
    end

    STORE = Rails.application.config.x.imports

    module_function

    def register(kind, importer:, policy:, module_key: nil)
      raise ArgumentError, "tipo de importación desconocido: #{kind.inspect}" unless Batch::KINDS.include?(kind.to_s)

      STORE.kinds = entries.merge(kind.to_s => Entry.new(kind: kind.to_s, importer:, policy:, module_key: module_key&.to_s))
    end

    def entries = STORE.kinds || {}

    def fetch(kind)
      (kind.is_a?(String) && entries[kind]) || raise(UnknownKind)
    end
  end
end
