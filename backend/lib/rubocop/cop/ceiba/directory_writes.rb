# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Tenancy::Directory returns `readonly` records and relations, but a relation allows bulk writes that bypass the
      # records (`update_all`, `delete_all`...) and `readonly(false)` lifts the protection. Outside the tenancy pack they
      # are forbidden on any chain starting at `Tenancy::Directory`. Known limit: it does not follow the relation if it
      # is first stored in a variable; CODEOWNERS reviews cover that.
      class DirectoryWrites < Base
        MSG = "No escribas a través de Tenancy::Directory (`%<method>s`): es de solo lectura. Las altas son Tenancy::ProvisionOrganization / AddCompany / AddBranch."

        WRITES = %i[update_all delete_all destroy_all update_columns update_column delete_by destroy_by insert_all upsert_all readonly].freeze
        RESTRICT_ON_SEND = WRITES

        def_node_matcher :directory?, "(const (const {nil? cbase} :Tenancy) :Directory)"

        def on_send(node)
          return if node.method?(:readonly) && !(node.first_argument&.false_type?)
          return if processed_source.file_path.to_s.include?("packs/platform/tenancy/")

          add_offense(node, message: format(MSG, method: node.method_name)) if rooted_in_directory?(node.receiver)
        end

        private

        def rooted_in_directory?(node)
          node = node.receiver while node&.send_type? && node.receiver
          directory?(node) || false
        end
      end
    end
  end
end
