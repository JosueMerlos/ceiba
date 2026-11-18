require "rails_helper"

# Access::UpdateBranding: the one write path of a company's branding. Validates every file BEFORE touching anything, stores
# the images, renders their variants with libvips (real, no mocks), audits the change in the caller's transaction and
# purges replaced blobs only once everything committed. ActiveStorage never enqueues a job.
RSpec.describe Access::UpdateBranding do
  let(:organization) { create(:organization) }
  let!(:company) { create_in(organization, :company) }

  # Each call is its own transaction (like a request): what waits for the outermost commit (rendered variant files, purges)
  # happens when it returns. A spec that wrapped everything in one tenant block would never reach that moment.
  def call(attributes: {}, files: {}, remove: [])
    with_tenant(organization) { described_class.call(company: Tenancy::Company.find(company.id), attributes:, files:, remove:) }
  end

  def stored = with_tenant(organization) { Tenancy::Company.find(company.id) }

  def logo_upload(color: [ 47, 138, 102 ], name: "logo.png")
    branding_upload(png_bytes(width: 300, height: 300, color:), filename: name, type: "image/png")
  end

  def audit_count = audit_events.size

  def audit_events = with_tenant(organization) { Audit::Event.where(action: "company.branding_updated").order(:id).to_a }

  # The variant as the proxy resolves it (decoded from its signed key), already rendered by the use case.
  def variant(kind, name) = stored.branding_variants(kind).fetch(name).processed

  def variant_image(kind, name) = Vips::Image.new_from_buffer(variant(kind, name).download, "")

  describe "textos, colores y fuente" do
    it "guarda los valores normalizados y audita el diff con before y after" do
      call(attributes: { brand_name: "Salón Estilo", primary_color: "#ffff00", font_choice: "lora" })

      expect(stored).to have_attributes(brand_name: "Salón Estilo", primary_color: "#FFFF00", font_choice: "lora")
      expect(audit_events).to contain_exactly(
        have_attributes(
          auditable_id: company.id, before: { "brand_name" => nil, "primary_color" => nil, "font_choice" => nil },
          after: { "brand_name" => "Salón Estilo", "primary_color" => "#FFFF00", "font_choice" => "lora" }
        )
      )
    end

    it "un valor vacío vuelve al default (nil) y se audita" do
      call(attributes: { tagline: "Corte y color" })

      call(attributes: { tagline: "" })

      expect([ stored.tagline, audit_events.last.after ]).to eq([ nil, { "tagline" => nil } ])
    end

    it "sin cambios efectivos no audita" do
      call(attributes: { primary_color: "#1D6C4E" })

      expect { call(attributes: { primary_color: "#1d6c4e" }) }.not_to change { audit_count }
    end

    it "un color inválido no persiste nada y responde con el error del campo" do
      expect { call(attributes: { brand_name: "Nuevo", primary_color: "amarillo" }) }.to raise_error(ActiveRecord::RecordInvalid) do |error|
        expect(error.record.errors.where(:primary_color).map(&:type)).to eq([ :invalid ])
      end
      expect([ stored.brand_name, audit_events ]).to eq([ nil, [] ])
    end
  end

  describe "archivos" do
    it "adjunta el logo con el tipo detectado, procesa sus dos variantes y las re-codifica a WebP del alto pedido" do
      call(files: { logo: logo_upload })

      expect([ stored.logo.content_type, variant_image(:logo, :x1).height, variant_image(:logo, :x2).height ]).to eq([ "image/png", 64, 128 ])
      expect(variant(:logo, :x1).image.content_type).to eq("image/webp")
    end

    it "procesa banner (16:9 y 4:3 en WebP) y favicon (32 y 180 en PNG)" do
      png = branding_upload(png_bytes(width: 400, height: 300), filename: "f.png", type: "image/png")

      call(files: { banner: logo_upload, favicon: png })

      sizes = [ %i[banner wide], %i[banner standard], %i[favicon icon32], %i[favicon icon180] ].map { |kind, name| variant_image(kind, name) }.map { [ it.width, it.height ] }
      expect(sizes).to eq([ [ 1600, 900 ], [ 1200, 900 ], [ 32, 32 ], [ 180, 180 ] ])
      expect(variant(:favicon, :icon32).image.content_type).to eq("image/png")
    end

    it "usa el tipo detectado y no el declarado" do
      upload = branding_upload(png_bytes(width: 300, height: 300), filename: "png-as.jpg", type: "image/jpeg")

      call(files: { logo: upload })

      expect(stored.logo.content_type).to eq("image/png")
    end

    it "audita el archivo nuevo con nombre, tamaño y checksum, sin su contenido" do
      call(files: { logo: logo_upload })

      blob = stored.logo.blob
      expect(audit_events.last.metadata).to eq("assets" => { "logo" => { "filename" => "logo.png", "byte_size" => blob.byte_size, "checksum" => blob.checksum } })
    end

    it "al reemplazar el logo cambia la clave del blob, cambia la variante y purga el blob y los archivos anteriores" do
      call(files: { logo: logo_upload })
      old_blob = stored.logo.blob
      old_variant_key = variant(:logo, :x1).key

      call(files: { logo: logo_upload(color: [ 200, 20, 20 ], name: "nuevo.png") })

      new_blob = stored.logo.blob
      expect(new_blob.key).not_to eq(old_blob.key)
      expect(new_blob.signed_id).not_to eq(old_blob.signed_id)
      expect(ActiveStorage::Blob.exists?(old_blob.id)).to be(false)
      expect(ActiveStorage::Blob.service.exist?(old_blob.key)).to be(false)
      expect(ActiveStorage::Blob.service.exist?(old_variant_key)).to be(false)
      expect(ActiveStorage::Blob.service.exist?(variant(:logo, :x1).key)).to be(true)
    end

    it "remove desadjunta, audita y purga el blob" do
      call(files: { logo: logo_upload })
      old_blob = stored.logo.blob

      call(remove: %w[logo])

      expect(stored.logo).not_to be_attached
      expect(ActiveStorage::Blob.exists?(old_blob.id)).to be(false)
      expect(audit_events.last.metadata).to eq("assets" => { "logo" => nil })
    end

    it "subir, reemplazar y quitar una imagen sube la versión de la empresa (lo que sigue el ETag público)" do
      versions = []
      versions << stored.cache_key_with_version
      call(files: { logo: logo_upload })
      versions << stored.cache_key_with_version
      call(files: { logo: logo_upload(color: [ 200, 20, 20 ]) })
      versions << stored.cache_key_with_version
      call(remove: %w[logo])
      versions << stored.cache_key_with_version

      expect(versions.uniq.size).to eq(4)
    end

    it "una petición sin cambios no sube la versión de la empresa" do
      before = stored.cache_key_with_version

      call(remove: %w[logo])

      expect(stored.cache_key_with_version).to eq(before)
    end

    it "quitar un adjunto que no existe no audita" do
      expect { call(remove: %w[logo]) }.not_to change { audit_count }
    end

    it "rechaza en remove lo que no es un adjunto de marca" do
      expect { call(remove: %w[organization]) }.to raise_error(ArgumentError, /organization/)
    end
  end

  describe "atomicidad" do
    it "un archivo inválido junto a colores válidos no persiste nada ni audita (invalid_file_type)" do
      svg = branding_upload(BrandingImages::SVG, filename: "svg-as.png", type: "image/png")

      expect { call(attributes: { primary_color: "#FFFF00" }, files: { logo: svg }) }.to raise_error(ActiveRecord::RecordInvalid) do |error|
        expect(error.record.errors.where(:logo).map(&:type)).to eq([ :invalid_file_type ])
      end
      expect([ stored.primary_color, stored.logo.attached?, audit_events, ActiveStorage::Blob.count ]).to eq([ nil, false, [], 0 ])
    end

    it "informa a la vez de los errores de campos y de archivos" do
      svg = branding_upload(BrandingImages::SVG, filename: "svg-as.png", type: "image/png")

      expect { call(attributes: { accent_color: "x" }, files: { logo: svg }) }.to raise_error(ActiveRecord::RecordInvalid) do |error|
        expect(error.record.errors.attribute_names).to contain_exactly(:accent_color, :logo)
      end
    end

    it "si la auditoría falla, el logo anterior sigue adjunto y su blob no se purga" do
      call(files: { logo: logo_upload })
      old_blob = stored.logo.blob
      allow(Audit).to receive(:record).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { ApplicationRecord.transaction { call(files: { logo: logo_upload(color: [ 1, 2, 3 ]) }) } }.to raise_error(ActiveRecord::StatementInvalid)

      expect(stored.logo.blob).to eq(old_blob)
      expect(ActiveStorage::Blob.service.exist?(old_blob.key)).to be(true)
    end
  end

  describe "trabajos en segundo plano" do
    it "ni subir, ni reemplazar, ni quitar encolan nada (no hay AnalyzeJob, PurgeJob ni TransformJob)" do
      call(files: { logo: logo_upload, banner: logo_upload })
      call(files: { logo: logo_upload(color: [ 9, 9, 9 ]) })
      call(remove: %w[banner])

      expect(Sidekiq::Queues.jobs_by_queue.values.flatten).to be_empty
    end
  end
end
