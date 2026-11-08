require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/tenant_bypass"

RSpec.describe RuboCop::Cop::Ceiba::TenantBypass, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) { { "AllowedFiles" => [ "packs/platform/tenancy/app/public/tenancy.rb", "app/reports/consolidated/**/*.rb" ] } }
  let(:file) { "packs/modules/appointments/app/services/appointments/book.rb" }

  context "con un archivo fuera de la lista permitida" do
    it "prohíbe ActsAsTenant.without_tenant" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.without_tenant { Appointment.count }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe la forma con :: inicial" do
      expect_offense(<<~RUBY, file)
        ::ActsAsTenant.without_tenant { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe ActsAsTenant.with_mutable_tenant" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.with_mutable_tenant { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `with_mutable_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe fijar el tenant fuera de Tenancy.with_context" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.with_tenant(org) { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `with_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe asignar current_tenant o unscoped en ActsAsTenant" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.current_tenant = org
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `current_tenant=` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        ActsAsTenant.unscoped = true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `unscoped=` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe Model.unscoped" do
      expect_offense(<<~RUBY, file)
        Appointment.unscoped.where(id: 1)
        ^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe unscoped con bloque y sin receptor" do
      expect_offense(<<~RUBY, file)
        unscoped { all }
        ^^^^^^^^ Ceiba/TenantBypass: `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "no confunde otros métodos ni otras constantes" do
      expect_no_offenses(<<~RUBY, file)
        Other.without_tenant { 1 }
        Tenancy.with_context(organization: org) { Appointment.count }
        ActsAsTenant.current_tenant
        relation.unscope(:where)
      RUBY
    end
  end

  context "con un archivo de la lista permitida" do
    it "admite Tenancy.with_context llamando a ActsAsTenant.with_tenant (el único sitio)" do
      expect_no_offenses(<<~RUBY, "packs/platform/tenancy/app/public/tenancy.rb")
        ActsAsTenant.with_tenant(organization) { 1 }
      RUBY
    end

    it "admite un patrón con glob (reportes consolidados)" do
      expect_no_offenses(<<~RUBY, "app/reports/consolidated/summary.rb")
        Appointment.unscoped.count
      RUBY
    end

    it "sigue prohibiendo en archivos que solo se parecen" do
      expect_offense(<<~RUBY, "packs/platform/tenancy/app/services/tenancy/other.rb")
        ActsAsTenant.without_tenant { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Ceiba/TenantBypass: `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end
  end
end
