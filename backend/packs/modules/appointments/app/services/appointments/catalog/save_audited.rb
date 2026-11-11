module Appointments
  module Catalog
    # Saves a record and audits the change in the same savepoint (a failed audit rolls the change back). `fields` are the
    # attributes recorded as before/after: Audit stores only the ones that differ. Nothing is audited when nothing changed.
    module SaveAudited
      module_function

      def call(record, action:, fields:, metadata: {})
        ApplicationRecord.transaction(requires_new: true) do
          before = record.new_record? ? nil : fields.to_h { [ it, record.attribute_in_database(it) ] }
          record.save!

          after = record.attributes.slice(*fields)
          Audit.record(action:, subject: record, before:, after:, metadata:) if before != after
        end
        record
      end
    end
  end
end
