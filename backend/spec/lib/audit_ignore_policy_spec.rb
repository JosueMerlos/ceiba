require "rails_helper"
require "audit_ignore_policy"

RSpec.describe AuditIgnorePolicy do
  subject(:violations) { described_class.new(yaml, today: Date.new(2026, 11, 8)).violations }

  context "con una lista vacía" do
    let(:yaml) { "ignore: []\n" }

    it { is_expected.to be_empty }
  end

  context "con un ignorado con fecha futura y motivo" do
    let(:yaml) { "ignore:\n  - CVE-2026-0001 # revisar: 2026-12-01 | motivo: sin ruta de explotación\n" }

    it { is_expected.to be_empty }
  end

  context "con un ignorado sin comentario" do
    let(:yaml) { "ignore:\n  - CVE-2026-0001\n" }

    it { is_expected.to contain_exactly(/CVE-2026-0001.*revisar.*motivo/) }
  end

  context "con ignorados en línea (sin comentario posible por entrada)" do
    let(:yaml) { "ignore: [CVE-2026-0001, CVE-2026-0002] # revisar: 2026-12-01 | motivo: x\n" }

    it { is_expected.to contain_exactly(/CVE-2026-0001/, /CVE-2026-0002/) }
  end

  context "con un ignorado sin motivo" do
    let(:yaml) { "ignore:\n  - CVE-2026-0001 # revisar: 2026-12-01 | motivo:\n" }

    it { is_expected.to contain_exactly(/CVE-2026-0001/) }
  end

  context "con la fecha de revisión vencida" do
    let(:yaml) { "ignore:\n  - CVE-2026-0001 # revisar: 2026-11-07 | motivo: x\n" }

    it { is_expected.to contain_exactly(/CVE-2026-0001.*vencid/) }
  end

  context "con una fecha inexistente" do
    let(:yaml) { "ignore:\n  - CVE-2026-0001 # revisar: 2026-13-45 | motivo: x\n" }

    it { is_expected.to contain_exactly(/CVE-2026-0001.*fecha/) }
  end

  context "con una mezcla de entradas válidas e inválidas" do
    let(:yaml) do
      "ignore:\n  - CVE-2026-0001 # revisar: 2026-12-01 | motivo: x\n  - CVE-2026-0002\n"
    end

    it { is_expected.to contain_exactly(/CVE-2026-0002/) }
  end

  context "sin la clave ignore" do
    let(:yaml) { "otra: clave\n" }

    it { is_expected.to contain_exactly(/ignore/) }
  end
end
