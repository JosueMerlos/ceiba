require "rails_helper"

RSpec.describe Access::Scope, ".from_context" do
  let(:organization) { Struct.new(:id).new("org-1") }
  let(:company) { Struct.new(:id).new("company-1") }
  let(:branch) { Struct.new(:id).new("branch-1") }
  let(:context) { Struct.new(:organization, :company, :branch).new(organization, company, branch) }

  it "a nivel :branch incluye organización, empresa y sucursal del contexto" do
    expect(described_class.from_context(context, level: :branch)).to eq(
      described_class.branch(organization_id: "org-1", company_id: "company-1", branch_id: "branch-1")
    )
  end

  it "a nivel :company omite la sucursal aunque el contexto la tenga" do
    expect(described_class.from_context(context, level: :company)).to eq(described_class.company(organization_id: "org-1", company_id: "company-1"))
  end

  it "un nivel desconocido es un error de código" do
    expect { described_class.from_context(context, level: :organization) }.to raise_error(ArgumentError, /desconocido/)
  end
end
