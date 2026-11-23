# A company's branding. Every column is nullable: NULL means "not customized", and the platform default applies. Colors are
# #RRGGBB in uppercase and the font is one of the curated families. The CHECKs are added NOT VALID and validated in their own
# migration (strong_migrations); there is nothing to backfill, so adding the columns does not lock the table.
class AddBrandingToCompanies < ActiveRecord::Migration[8.1]
  COLOR_COLUMNS = %i[primary_color secondary_color accent_color].freeze

  def change
    add_column :companies, :brand_name, :string, limit: 80
    add_column :companies, :tagline, :string, limit: 140
    COLOR_COLUMNS.each { |column| add_column :companies, column, :string, limit: 7 }
    add_column :companies, :font_choice, :string

    COLOR_COLUMNS.each do |column|
      add_check_constraint :companies, "#{column} IS NULL OR #{column} ~ '^#[0-9A-F]{6}$'", name: "chk_companies_#{column}_format", validate: false
    end
    add_check_constraint :companies, "font_choice IS NULL OR font_choice = 'figtree' OR font_choice = 'lora' OR font_choice = 'nunito'",
      name: "chk_companies_font_choice", validate: false
  end
end
