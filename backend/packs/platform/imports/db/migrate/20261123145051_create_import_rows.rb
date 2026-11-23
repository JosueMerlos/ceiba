# import_rows: one data row of a batch. `payload` holds the row's cells (personal data for customers), encrypted and
# erased as soon as the row is processed or the batch expires; `error_codes` keeps {column => code} for the report, never
# a value.
class CreateImportRows < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :import_rows do |t|
      # No own index: the unique one below starts with (organization_id, import_batch_id).
      t.tenant_reference :import_batch, index: false
      t.integer :row_number, null: false
      t.string :status, null: false
      t.text :payload
      t.jsonb :error_codes, null: false, default: {}
      t.timestamps

      t.check_constraint "row_number > 0", name: "chk_import_rows_row_number_positive"
      t.check_constraint "status = 'ready' OR status = 'rejected' OR status = 'created' OR status = 'updated' OR status = 'restored' OR status = 'skipped' OR status = 'failed'", name: "chk_import_rows_status"

      t.index %i[organization_id import_batch_id row_number], unique: true, name: "uq_import_rows_batch_row"
    end
  end
end
