require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/appointment_creation"

# Appointments::Book is the only creator of appointments: it takes the locks and revalidates before inserting. Any other way
# in would skip both.
RSpec.describe RuboCop::Cop::Ceiba::AppointmentCreation, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) { { "AllowedFiles" => [ "packs/modules/appointments/app/public/appointments/book.rb" ] } }
  let(:file) { "packs/modules/appointments/app/services/appointments/reschedule.rb" }

  context "con un archivo fuera de la lista permitida" do
    %w[create create! new insert insert! insert_all insert_all! upsert upsert_all find_or_create_by find_or_create_by!
       first_or_create first_or_create! create_or_find_by create_or_find_by! build find_or_initialize_by first_or_initialize create_with].each do |method|
      it "prohíbe Appointments::Appointment.#{method}" do
        expect_offense(<<~RUBY, file)
          Appointments::Appointment.#{method}(status: "scheduled")
          ^^^^^^^^^^^^^^^^^^^^^^^^^^#{'^' * method.length}^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`#{method}` se salta los candados y la revalidación).
        RUBY
      end
    end

    it "prohíbe crear desde una cadena que parte del modelo" do
      expect_offense(<<~RUBY, file)
        Appointments::Appointment.where(status: "scheduled").create!(notes: "x")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`create!` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe construir desde una cadena que parte del modelo (build y create_with)", :aggregate_failures do
      expect_offense(<<~RUBY, file)
        Appointment.where(status: "scheduled").build(notes: "x")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`build` se salta los candados y la revalidación).
      RUBY
      expect_offense(<<~RUBY, file)
        Appointments::Appointment.create_with(source: "panel").find_or_initialize_by(id: id)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`find_or_initialize_by` se salta los candados y la revalidación).
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`create_with` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe first_or_create! tras un scope" do
      expect_offense(<<~RUBY, file)
        Appointment.blocking.first_or_create!(status: "scheduled")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`first_or_create!` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe crear líneas de servicio de una cita fuera de Book" do
      expect_offense(<<~RUBY, file)
        Appointments::AppointmentService.create!(appointment_id: id)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`create!` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe AppointmentService.insert_all dentro del módulo" do
      expect_offense(<<~RUBY, file)
        AppointmentService.insert_all(rows)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`insert_all` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe Appointment.create! dentro del módulo" do
      expect_offense(<<~RUBY, file)
        Appointment.create!(status: "scheduled")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`create!` se salta los candados y la revalidación).
      RUBY
    end

    it "prohíbe la forma con :: inicial" do
      expect_offense(<<~RUBY, file)
        ::Appointments::Appointment.new(status: "scheduled")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`new` se salta los candados y la revalidación).
      RUBY
    end

    it "acepta leer y actualizar citas" do
      expect_no_offenses(<<~RUBY, file)
        Appointments::Appointment.where(status: "scheduled").update_all(status: "cancelled")
        Appointment.find(id)
        Appointment.blocking.where(professional_id: id).first
        AppointmentService.where(appointment_id: id).order(:position).to_a
      RUBY
    end

    it "acepta el Appointment de otro namespace" do
      expect_no_offenses("Other::Appointment.create(name: 'x')", file)
    end
  end

  context "con el archivo de Book" do
    it "acepta crear la cita" do
      expect_no_offenses("Appointment.create!(status: 'scheduled')", "packs/modules/appointments/app/public/appointments/book.rb")
    end

    it "lo reconoce con la ruta desde la raíz del repositorio o absoluta, no solo desde backend/", :aggregate_failures do
      expect_no_offenses("Appointment.create!(status: 'scheduled')", "backend/packs/modules/appointments/app/public/appointments/book.rb")
      expect_no_offenses("Appointment.create!(status: 'scheduled')", "/app/backend/packs/modules/appointments/app/public/appointments/book.rb")
    end

    it "no confunde otro archivo con el mismo nombre en otra ruta" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/services/appointments/book.rb")
        Appointment.create!(status: "scheduled")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Crear citas es solo de Appointments::Book (`create!` se salta los candados y la revalidación).
      RUBY
    end
  end

  # The cop only sees the files .rubocop.yml hands it: seeds, initializers and rake tasks create data too.
  describe "los archivos que revisa (.rubocop.yml)" do
    let(:project_config) { RuboCop::ConfigLoader.configuration_from_file(Rails.root.join(".rubocop.yml").to_s) }
    let(:cop) { described_class.new(project_config) }

    %w[
      packs/modules/appointments/app/services/appointments/reschedule.rb
      packs/modules/appointments/db/seeds.rb
      packs/modules/appointments/db/migrate/20261112200200_recreate.rb
      packs/modules/appointments/config/initializers/seed.rb
      lib/tasks/demo.rake
      packs/modules/appointments/lib/tasks/demo.rake
      db/seeds.rb
    ].each do |path|
      it "incluye #{path}" do
        expect(cop.relevant_file?(Rails.root.join(path).to_s)).to be(true)
      end
    end

    it "sigue excluyendo los specs" do
      expect(cop.relevant_file?(Rails.root.join("packs/modules/appointments/spec/factories/appointments.rb").to_s)).to be(false)
    end
  end
end
