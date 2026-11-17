require "rails_helper"

# The branding columns of a company: NULL means "not customized" (the platform default applies), colors are #RRGGBB
# normalized to uppercase, the font is one of the curated families. The database repeats the format and font checks.
RSpec.describe Tenancy::Company::Branding do
  let(:organization) { create(:organization) }

  around { |example| with_tenant(organization) { example.run } }

  def company(**attributes) = build(:company, **attributes)

  describe "colores" do
    it "normaliza a mayúsculas" do
      expect(company(primary_color: "#ffff00").tap(&:valid?).primary_color).to eq("#FFFF00")
    end

    it "convierte un valor vacío en nil (vuelve al default de la plataforma)" do
      expect(company(primary_color: "", secondary_color: "  ").tap(&:valid?).attributes.values_at("primary_color", "secondary_color")).to eq([ nil, nil ])
    end

    it "acepta nil en los tres colores" do
      expect(company(primary_color: nil, secondary_color: nil, accent_color: nil)).to be_valid
    end

    [ "#FFF", "FFFF00", "#GGGGGG", "#FFFF 00", "#FFFF00 ", "#FFFF000", "rgb(0,0,0)" ].each do |value|
      it "rechaza #{value.inspect}" do
        record = company(accent_color: value)

        expect([ record.valid?, record.errors.where(:accent_color).map(&:type) ]).to eq([ false, [ :invalid ] ])
      end
    end
  end

  describe "fuente" do
    it "acepta las tres familias curadas y nil" do
      expect(%w[figtree lora nunito nil].map { |key| company(font_choice: key == "nil" ? nil : key).valid? }).to all(be(true))
    end

    it "rechaza una familia fuera de la lista" do
      record = company(font_choice: "comic-sans")

      expect([ record.valid?, record.errors.where(:font_choice).map(&:type) ]).to eq([ false, [ :inclusion ] ])
    end
  end

  describe "textos" do
    it "acepta un nombre de 80 y un lema de 140 caracteres, y rechaza uno más" do
      accepted = company(brand_name: "a" * 80, tagline: "b" * 140)
      rejected = company(brand_name: "a" * 81, tagline: "b" * 141)

      expect([ accepted.valid?, rejected.valid?, rejected.errors.attribute_names ]).to eq([ true, false, %i[brand_name tagline] ])
    end
  end

  describe "base de datos" do
    it "rechaza un color inválido escrito sin pasar por las validaciones" do
      record = create(:company)

      expect { savepoint { record.update_columns(primary_color: "#fff") } }.to raise_error(ActiveRecord::StatementInvalid, /chk_companies_primary_color_format/)
    end

    it "rechaza una fuente fuera de la lista escrita sin pasar por las validaciones" do
      record = create(:company)

      expect { savepoint { record.update_columns(font_choice: "comic-sans") } }.to raise_error(ActiveRecord::StatementInvalid, /chk_companies_font_choice/)
    end

    it "rechaza un color en minúsculas escrito sin pasar por el modelo (que lo normalizaría)" do
      record = create(:company)

      expect { savepoint { Tenancy::Company.connection.execute("UPDATE companies SET secondary_color = '#ffff00' WHERE id = '#{record.id}'") } }.to raise_error(ActiveRecord::StatementInvalid, /chk_companies_secondary_color_format/)
    end
  end

  describe "adjuntos" do
    it "declara logo, banner y favicon" do
      expect(Tenancy::Company.attachment_reflections.keys).to contain_exactly("logo", "banner", "favicon")
    end
  end
end
