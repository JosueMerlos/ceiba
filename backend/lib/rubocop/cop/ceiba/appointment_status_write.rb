# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Appointments::Transition is the only writer of an appointment's status: it locks the row, applies the transition table and
      # publishes and audits the change in the same transaction. Writing `status` any other way skips all of that. Flagged on ANY
      # receiver, because an appointment usually travels in a variable: a hash with a `status` key passed to a writer
      # (`update!(status: ...)`, `update_all("status" => ...)`), an `update_all` with SQL that mentions `status`, a single-attribute
      # writer named `status` (`update_column(:status, ...)`, `[:status] =`) and `status=`. The Include of .rubocop.yml limits it
      # to the appointments pack (the model is private to it), where no other record has a status.
      # Known limits: a hash built elsewhere and passed as a variable, a dynamic attribute name and `send(:status=)` are not followed.
      #
      # @example
      #   # bad
      #   appointment.update!(status: "cancelled")
      #
      #   # good
      #   Appointments::Cancel.call(appointment:, reason: "other", cancelled_by: "staff")
      class AppointmentStatusWrite < Base
        MSG = "El estado de una cita solo lo cambia Appointments::Transition (`%<method>s` se salta el bloqueo, la tabla de " \
              "transiciones, el evento y la auditoría)."

        HASH_WRITERS = %i[update update! update_columns update_all assign_attributes attributes= upsert].freeze
        ATTRIBUTE_WRITERS = %i[update_column update_attribute write_attribute []=].freeze
        RESTRICT_ON_SEND = (HASH_WRITERS + ATTRIBUTE_WRITERS + %i[status=]).freeze

        def on_send(node)
          return unless status_write?(node)
          return if allowed_file?

          add_offense(node, message: format(MSG, method: node.method_name))
        end
        alias on_csend on_send

        private

        def status_write?(node)
          name = node.method_name
          return true if name == :status=
          return status_key?(node.first_argument) if ATTRIBUTE_WRITERS.include?(name)

          node.arguments.any? { status_hash?(it) } || (name == :update_all && status_sql?(node.first_argument))
        end

        def status_hash?(argument) = argument&.hash_type? && argument.pairs.any? { status_key?(it.key) }

        def status_key?(node) = (node&.sym_type? || node&.str_type?) && node.value.to_s == "status"

        def status_sql?(argument) = (argument&.str_type? || argument&.dstr_type?) && argument.source.match?(/\bstatus\b/)

        # Matched by the end of the path, like AppointmentCreation, so the working directory RuboCop runs from does not matter.
        def allowed_file?
          path = processed_source.file_path.to_s
          Array(cop_config["AllowedFiles"]).any? { |pattern| File.fnmatch?("**/#{pattern}", path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end
    end
  end
end
