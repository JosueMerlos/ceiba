# Una sucursal es identificable también por (organization_id, company_id, id): permite que otras tablas (memberships,
# M0.08) referencien una sucursal CON su empresa mediante una FK compuesta, y que la base impida un membership de
# sucursal cuya company_id no sea la de esa sucursal. El índice es único porque `id` ya lo es.
class AddCompanyScopedUniqueIndexToBranches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :branches, %i[organization_id company_id id], unique: true, algorithm: :concurrently,
      name: "uq_branches_organization_id_company_id_id"
  end
end
