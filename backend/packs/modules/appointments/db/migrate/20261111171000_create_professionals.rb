# professionals: the people who attend, one record PER COMPANY. user_id optionally links the record to a person (a global
# user); the same person may have a record in every company of the group, each with its own schedule, but at most one in a
# company (partial unique index). A professional is archived (archived_at), never deleted: bookings will reference it.
#
# UNIQUE (organization_id, company_id, id) is the target of the composite FKs from the assignments and the services a
# professional performs, which is what makes the database refuse to mix a professional of one company with a branch or a
# service of another.
class CreateProfessionals < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :professionals do |t|
      # No (organization_id, company_id) index: the listing index below already covers it.
      t.tenant_reference :company, index: false
      t.references :user, type: :uuid, null: true, index: false, foreign_key: { name: "fk_professionals_user" }
      t.string :display_name, null: false
      t.boolean :active, null: false, default: true
      t.datetime :archived_at
      t.timestamps

      t.check_constraint "length(btrim(display_name)) > 0", name: "chk_professionals_name_present"

      t.index %i[organization_id company_id id], unique: true, name: "uq_professionals_org_company_id"
      # One record per person in a company; records without a linked person are unlimited.
      t.index %i[company_id user_id], unique: true, where: "user_id IS NOT NULL", name: "uq_professionals_company_user"
      # The listing: non-archived professionals of a company, paginated by id.
      t.index %i[organization_id company_id id], where: "archived_at IS NULL", name: "idx_professionals_company_unarchived_id"
      # "Which professional records does this person have?"
      t.index :user_id, where: "user_id IS NOT NULL", name: "idx_professionals_user"
    end
  end
end
