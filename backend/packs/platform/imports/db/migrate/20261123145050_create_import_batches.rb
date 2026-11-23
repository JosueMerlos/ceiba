# import_batches: one uploaded CSV (customers, services or professionals) from preview to its final report. Holds counts
# and codes only, never cell values or the file name (both may be personal data): those live, encrypted and short-lived,
# in import_rows.
class CreateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :import_batches do |t|
      t.tenant_reference :company, index: false
      t.tenant_reference :branch, index: false
      t.string :kind, null: false
      t.string :status, null: false, default: "previewed"
      t.string :duplicate_mode
      t.uuid :created_by_id, null: false
      t.jsonb :warnings, null: false, default: []
      %i[total ready rejected created updated restored skipped failed].each do |counter|
        t.integer :"#{counter}_count", null: false, default: 0
      end
      t.datetime :expires_at, null: false
      t.datetime :confirmed_at
      t.datetime :finished_at
      t.timestamps

      t.check_constraint "kind = 'customers' OR kind = 'services' OR kind = 'professionals'", name: "chk_import_batches_kind"
      t.check_constraint "status = 'previewed' OR status = 'queued' OR status = 'processing' OR status = 'completed' OR status = 'failed' OR status = 'expired'", name: "chk_import_batches_status"
      t.check_constraint "duplicate_mode IS NULL OR duplicate_mode = 'skip' OR duplicate_mode = 'update'", name: "chk_import_batches_duplicate_mode"

      # Two batches of the same kind running at once would race on the same natural keys (services and professionals have
      # no unique name), so a company runs one at a time per kind.
      t.index %i[organization_id company_id kind], unique: true, where: "status = 'queued' OR status = 'processing'", name: "uq_import_batches_running"
      t.index %i[organization_id company_id id], name: "idx_import_batches_company_id"
      # The purge looks for unconfirmed batches past their expiry and stuck ones, across organizations.
      t.index %i[status expires_at], name: "idx_import_batches_status_expires"
    end
  end
end
