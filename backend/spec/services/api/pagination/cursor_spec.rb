require "rails_helper"

# Criterio 6 de M0.06 y docs/architecture/07-api-contract.md: paginación por cursor sobre UUIDv7. El orden es el de la
# clave primaria (que es temporal), no hay OFFSET, y el cursor es opaco y FIRMADO.
RSpec.describe Api::Pagination::Cursor do
  def create_organizations(count)
    Array.new(count) { create(:organization) }
  end

  def walk(scope, limit:, &between_pages)
    pages = []
    after = nil
    loop do
      page = described_class.paginate(scope, limit:, after:)
      pages << page
      break unless page.has_more

      between_pages&.call(pages.size)
      after = page.next_cursor
    end
    pages
  end

  let(:scope) { Tenancy::Organization.all }

  describe "con 120 registros y limit=50 (criterio 6)" do
    it "entrega 3 páginas (50, 50 y 20) sin duplicados ni omisiones, en el orden de la clave" do
      ids = create_organizations(120).map(&:id)

      pages = walk(scope, limit: 50)

      expect(pages.map { |page| page.records.size }).to eq([ 50, 50, 20 ])
      expect(pages.map(&:has_more)).to eq([ true, true, false ])
      expect(pages.flat_map { |page| page.records.map(&:id) }).to eq(ids)
    end

    it "no duplica ni omite ninguno de los 120 aunque se inserten registros entre páginas" do
      originals = create_organizations(120).map(&:id)
      inserted = []

      pages = walk(scope, limit: 50) { |_page_number| inserted.concat(create_organizations(7).map(&:id)) }

      seen = pages.flat_map { |page| page.records.map(&:id) }
      expect(seen).to eq(seen.uniq)
      expect(seen.first(120)).to eq(originals)
      expect(seen - originals).to match_array(inserted.first(seen.size - 120))
    end

    it "el orden es estable: los registros nuevos (UUIDv7 mayores) quedan al final, nunca entre los ya entregados" do
      first_ids = create_organizations(3).map(&:id)
      page = described_class.paginate(scope, limit: 2)
      newcomer = create(:organization)

      rest = described_class.paginate(scope, limit: 10, after: page.next_cursor)

      expect(rest.records.map(&:id)).to eq([ first_ids.last, newcomer.id ])
    end
  end

  describe "has_more y next_cursor" do
    it "con exactamente limit registros no hay más páginas (no devuelve una página vacía de más)" do
      create_organizations(4)

      page = described_class.paginate(scope, limit: 4)

      expect(page).to have_attributes(has_more: false, next_cursor: nil)
      expect(page.records.size).to eq(4)
    end

    it "sin registros devuelve una página vacía" do
      page = described_class.paginate(scope, limit: 10)

      expect(page).to have_attributes(records: [], has_more: false, next_cursor: nil)
    end

    it "usa 50 por defecto" do
      create_organizations(51)

      expect(described_class.paginate(scope).records.size).to eq(50)
    end
  end

  describe "el scope recibido" do
    it "conserva sus filtros y descarta su orden" do
      active = create_organizations(3)
      create(:organization, status: "suspended")

      page = described_class.paginate(Tenancy::Organization.where(status: "active").order(name: :desc), limit: 10)

      expect(page.records.map(&:id)).to eq(active.map(&:id))
    end

    it "pide limit + 1 filas a la base y no cuenta ni usa OFFSET" do
      create_organizations(3)
      sql = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| sql << payload[:sql] }

      described_class.paginate(scope, limit: 2)

      expect(sql.grep(/FROM "organizations"/)).to all(match(/LIMIT \$?\d+|LIMIT 3/)).and(satisfy { |list| list.none?(/OFFSET|COUNT/i) })
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  describe "el límite" do
    it "rechaza valores no enteros, cero, negativos y por encima del máximo" do
      [ "abc", "0", "-5", "1.5", "101", "" ].each do |limit|
        expect { described_class.paginate(scope, limit:) }
          .to raise_error(Api::Pagination::InvalidLimit), "limit=#{limit.inspect} debía rechazarse"
      end
    end

    it "acepta un entero como texto (viene de la query string) y el máximo de 100" do
      create_organizations(3)

      expect(described_class.paginate(scope, limit: "2").records.size).to eq(2)
      expect { described_class.paginate(scope, limit: "100") }.not_to raise_error
    end
  end

  describe "el cursor" do
    it "es una cadena opaca apta para URL, sin el UUID a la vista" do
      create_organizations(3)

      cursor = described_class.paginate(scope, limit: 1).next_cursor

      expect(cursor).to match(/\A[A-Za-z0-9_\-=.]+\z/)
      expect(cursor).not_to match(/\h{8}-\h{4}-/)
    end

    it "rechaza un cursor manipulado" do
      create_organizations(3)
      cursor = described_class.paginate(scope, limit: 1).next_cursor
      tampered = cursor.sub(/.\z/) { |last| last == "A" ? "B" : "A" }

      expect { described_class.paginate(scope, after: tampered) }.to raise_error(Api::Pagination::InvalidCursor)
    end

    it "rechaza un cursor inventado, vacío o que no es texto" do
      [ "no-es-un-cursor", "", "a.b.c", "eyJpZCI6IjEifQ==--firma" ].each do |after|
        expect { described_class.paginate(scope, after:) }.to raise_error(Api::Pagination::InvalidCursor)
      end
    end

    it "rechaza un cursor firmado con la misma clave pero para otro propósito (no se puede forjar con otro verificador)" do
      forged = Rails.application.message_verifier("otra.cosa").generate({ "id" => SecureRandom.uuid }, purpose: :cursor)

      expect { described_class.paginate(scope, after: forged) }.to raise_error(Api::Pagination::InvalidCursor)
    end

    it "rechaza un cursor bien firmado cuyo contenido no es un UUID" do
      signed = described_class.send(:verifier).generate({ "id" => "no-uuid" }, purpose: :cursor)

      expect { described_class.paginate(scope, after: signed) }.to raise_error(Api::Pagination::InvalidCursor)
    end
  end
end
