class ValidateCompaniesBrandingChecks < ActiveRecord::Migration[8.1]
  def change
    %w[primary_color secondary_color accent_color].each { |column| validate_check_constraint :companies, name: "chk_companies_#{column}_format" }
    validate_check_constraint :companies, name: "chk_companies_font_choice"
  end
end
