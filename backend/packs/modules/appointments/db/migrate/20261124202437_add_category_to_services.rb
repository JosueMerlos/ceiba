# A free-text group for the catalog. NULL means "no category", never a blank string; the CHECK is added NOT VALID and
# validated in its own migration.
class AddCategoryToServices < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :category, :string, limit: 60
    add_check_constraint :services, "category IS NULL OR length(btrim(category)) > 0", name: "chk_services_category_present", validate: false
  end
end
