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
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe la forma con :: inicial" do
      expect_offense(<<~RUBY, file)
        ::ActsAsTenant.without_tenant { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe ActsAsTenant.with_mutable_tenant" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.with_mutable_tenant { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `with_mutable_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe fijar el tenant fuera de Tenancy.with_context" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.with_tenant(org) { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `with_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe asignar current_tenant o unscoped en ActsAsTenant" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant.current_tenant = org
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `current_tenant=` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        ActsAsTenant.unscoped = true
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `unscoped=` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe Model.unscoped" do
      expect_offense(<<~RUBY, file)
        Appointment.unscoped.where(id: 1)
        ^^^^^^^^^^^^^^^^^^^^ `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe unscoped con bloque y sin receptor" do
      expect_offense(<<~RUBY, file)
        unscoped { all }
        ^^^^^^^^ `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe quitar la condición del tenant con unscope(:where) o unscope(where: ...)" do
      expect_offense(<<~RUBY, file)
        Appointment.unscope(:where)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `unscope` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.unscope(where: :organization_id)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `unscope` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe rewhere sobre organization_id" do
      expect_offense(<<~RUBY, file)
        Appointment.rewhere(organization_id: other_id)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `rewhere` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe except(:where) y only(...) sobre una relación" do
      expect_offense(<<~RUBY, file)
        scope.except(:where)
        ^^^^^^^^^^^^^^^^^^^^ `except` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        scope.only(:order)
        ^^^^^^^^^^^^^^^^^^ `only` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe llegar al bypass con send, public_send y __send__" do
      expect_offense(<<~RUBY, file)
        Appointment.send(:unscoped)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        ActsAsTenant.public_send("without_tenant") { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.__send__(:unscope, :where)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `unscope` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe escribir en ActsAsTenant::Current" do
      expect_offense(<<~RUBY, file)
        ActsAsTenant::Current.current_tenant = org
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `current_tenant=` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        ::ActsAsTenant::Current.set(current_tenant: org) { 1 }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `set` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe las escrituras masivas que se saltan callbacks y validaciones" do
      expect_offense(<<~RUBY, file)
        Appointment.upsert_all(rows, unique_by: :id)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `upsert_all` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.insert_all(rows)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `insert_all` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.insert_all!(rows)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `insert_all!` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.upsert(row)
        ^^^^^^^^^^^^^^^^^^^^^^^ `upsert` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        Appointment.insert!(row)
        ^^^^^^^^^^^^^^^^^^^^^^^^ `insert!` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "prohíbe update_all, update_columns y update_column que escriben organization_id" do
      expect_offense(<<~RUBY, file)
        Appointment.update_all(organization_id: other)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `update_all` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        record.update_columns(organization_id: other, name: "x")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `update_columns` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
        record.update_column(:organization_id, other)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `update_column` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "no marca update_all/update_columns de otros atributos ni insert de colecciones" do
      expect_no_offenses(<<~RUBY, file)
        Appointment.update_all(status: "x")
        record.update_columns(name: "x")
        record.update_column(:name, "x")
        list.insert(1, item)
        text.insert!(0, "a")
      RUBY
    end

    it "revisa también las tareas rake" do
      expect_offense(<<~RUBY, "lib/tasks/reports.rake")
        task(report: :environment) { Appointment.unscoped.count }
                                     ^^^^^^^^^^^^^^^^^^^^ `unscoped` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end

    it "no marca unscope de otras cláusulas ni where normal" do
      expect_no_offenses(<<~RUBY, file)
        scope.unscope(:order)
        scope.where(status: "x").rewhere(status: "y")
        scope.except(:order)
        scope.send(:name)
      RUBY
    end

    it "no confunde otros métodos ni otras constantes" do
      expect_no_offenses(<<~RUBY, file)
        Other.without_tenant { 1 }
        Tenancy.with_context(organization: org) { Appointment.count }
        ActsAsTenant.current_tenant
        relation.unscope(:order)
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
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ `without_tenant` salta el aislamiento de tenant: usa `Tenancy.with_context` (o añade el archivo a AllowedFiles tras revisión).
      RUBY
    end
  end
end
