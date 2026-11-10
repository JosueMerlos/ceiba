require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/directory_writes"

# Tenancy::Directory returns readonly records and relations, but a relation allows update_all/delete_all (which bypass
# the records) and readonly(false). Outside tenancy they are detected statically.
RSpec.describe RuboCop::Cop::Ceiba::DirectoryWrites, :config do
  let(:ruby_version) { 3.4 }
  let(:cop_config) { { "Include" => [ "packs/*/*/app/**/*.rb", "app/**/*.rb" ] } }

  def flagged(body, path = "packs/platform/access/app/services/access/x.rb") = inspect_source(body, path).map { |offense| offense.location.source }

  it "acepta leer del Directory" do
    expect(flagged("Tenancy::Directory.companies.where(id: 1).to_a")).to be_empty
  end

  it "rechaza update_all, delete_all, destroy_all y readonly(false) sobre una relación del Directory" do
    expect(flagged("::Tenancy::Directory.companies.update_all(name: 'x')\nTenancy::Directory.branches.where(a: 1).delete_all\nTenancy::Directory.organizations_for([]).readonly(false)")).to eq(
      [ "::Tenancy::Directory.companies.update_all(name: 'x')", "Tenancy::Directory.branches.where(a: 1).delete_all", "Tenancy::Directory.organizations_for([]).readonly(false)" ]
    )
  end

  it "no revisa el propio pack tenancy" do
    expect(flagged("Tenancy::Directory.companies.delete_all", "packs/platform/tenancy/app/public/tenancy/directory.rb")).to be_empty
  end
end
