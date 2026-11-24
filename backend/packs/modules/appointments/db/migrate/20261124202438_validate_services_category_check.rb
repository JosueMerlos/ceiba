class ValidateServicesCategoryCheck < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :services, name: "chk_services_category_present"
  end
end
