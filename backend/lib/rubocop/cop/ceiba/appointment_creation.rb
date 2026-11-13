# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Ceiba
      # Appointments::Book is the only creator of appointments: it takes the locks and asks the availability engine again before
      # the INSERT. Creating one any other way skips both and can leave the agenda inconsistent. The allowed files (AllowedFiles)
      # are the ones that hold that creation; specs are excluded in .rubocop.yml because the factory is test infrastructure.
      # Known limit: it matches the constant by name, so an alias stored in a variable or `constantize` is not followed.
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
        ].freeze
        RESTRICT_ON_SEND = CREATORS

        # @!method appointment_model?(node)
        def_node_matcher :appointment_model?, <<~PATTERN
          {(const {nil? cbase} :Appointment) (const (const {nil? cbase} :Appointments) :Appointment)}
        PATTERN

        def on_send(node)
          return unless appointment_model?(node.receiver)
          return if allowed_file?

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        private

        def allowed_file?
          relative = PathUtil.relative_path(processed_source.file_path.to_s)
          Array(cop_config["AllowedFiles"]).any? { |pattern| File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end
    end
  end
end
