# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Appointments::Book is the only creator of appointments and of their service lines (the price snapshot): it takes the locks
      # and asks the availability engine again before the INSERT. Creating one any other way skips both and can leave the agenda
      # inconsistent. A creator is flagged on the model itself or at the end of a chain that starts there (`Appointment.where(...)
      # .create!`). The allowed files (AllowedFiles) are the ones that hold that creation; specs are excluded in .rubocop.yml because
      # the factory is test infrastructure.
      # Known limit: it matches the constants by name, so an alias stored in a variable, `constantize` or creating through an
      # association (`appointment.services_snapshot.create!`) is not followed.
      #
      # @example
      #   # bad
      #   Appointments::Appointment.create!(professional_id: id, starts_at: time)
      #
      #   # good
      #   Appointments::Book.call(company:, branch:, customer_id:, services:, professional:, starts_at:, source: "panel")
      class AppointmentCreation < Base
        MSG = "Crear citas es solo de Appointments::Book (`%<method>s` se salta los candados y la revalidación)."

        CREATORS = %i[
          create create! new insert insert! insert_all insert_all! upsert upsert_all find_or_create_by find_or_create_by!
          first_or_create first_or_create! create_or_find_by create_or_find_by! build find_or_initialize_by first_or_initialize create_with
        ].freeze
        RESTRICT_ON_SEND = CREATORS

        # @!method appointment_model?(node)
        def_node_matcher :appointment_model?, <<~PATTERN
          {(const {nil? cbase} {:Appointment :AppointmentService}) (const (const {nil? cbase} :Appointments) {:Appointment :AppointmentService})}
        PATTERN

        def on_send(node)
          return unless appointment_model?(chain_root(node.receiver))
          return if allowed_file?

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        private

        def chain_root(node)
          node = node.receiver while node&.send_type?
          node
        end

        # The patterns are written from the project root (backend/), but RuboCop may run from the repository root, from a pack or
        # with absolute paths: matching the end of the path keeps the allowlist independent of the working directory.
        def allowed_file?
          path = processed_source.file_path.to_s
          Array(cop_config["AllowedFiles"]).any? { |pattern| File.fnmatch?("**/#{pattern}", path, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end
    end
  end
end
