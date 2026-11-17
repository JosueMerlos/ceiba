require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/appointment_status_write"

# Appointments::Transition is the only writer of an appointment's status: it locks the row, applies the transition table and
# publishes and audits the change. Any other write would skip all of that.
RSpec.describe RuboCop::Cop::Ceiba::AppointmentStatusWrite, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) { { "AllowedFiles" => [ "packs/modules/appointments/app/public/appointments/transition.rb" ] } }
  let(:file) { "packs/modules/appointments/app/controllers/api/v1/appointments/appointments_controller.rb" }

  def message(method) = "El estado de una cita solo lo cambia Appointments::Transition (`#{method}` se salta el bloqueo, la tabla de transiciones, el evento y la auditoría)."

  context "con un archivo fuera de la lista permitida" do
    %w[update update! update_columns assign_attributes upsert].each do |method|
      it "prohíbe #{method} con la clave status, como símbolo y como string", :aggregate_failures do
        expect_offense(<<~RUBY, file, method:)
          appointment.#{method}(status: "cancelled", notes: "x")
          ^^^^^^^^^^^^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message(method)}
        RUBY
        expect_offense(<<~RUBY, file, method:)
          appointment.#{method}("status" => "cancelled")
          ^^^^^^^^^^^^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^ #{message(method)}
        RUBY
      end
    end

    it "prohíbe update_all sobre una cadena del modelo, con hash o con SQL", :aggregate_failures do
      expect_offense(<<~RUBY, file)
        Appointments::Appointment.where(id: id).update_all(status: "completed")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('update_all')}
      RUBY
      expect_offense(<<~RUBY, file)
        Appointment.where(id: id).update_all("status = 'completed', updated_at = now()")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('update_all')}
      RUBY
    end

    %w[update_column update_attribute write_attribute []=].each do |method|
      it "prohíbe #{method} del atributo status" do
        source = method == "[]=" ? 'appointment[:status] = "no_show"' : "appointment.#{method}(:status, \"no_show\")"
        expect_offense(<<~RUBY, file)
          #{source}
          #{'^' * source.length} #{message(method)}
        RUBY
      end
    end

    it "prohíbe attributes= con la clave status" do
      expect_offense(<<~RUBY, file)
        appointment.attributes = { status: "cancelled" }
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('attributes=')}
      RUBY
    end

    %w[insert insert!].each do |method|
      it "prohíbe #{method} con una fila que lleva status" do
        expect_offense(<<~RUBY, file, method:)
          Appointment.#{method}({ id: id, status: "completed" })
          ^^^^^^^^^^^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message(method)}
        RUBY
      end
    end

    it "prohíbe update_all con SQL y parámetros (array)" do
      expect_offense(<<~RUBY, file)
        Appointment.where(id: id).update_all([ "status = ?", "completed" ])
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('update_all')}
      RUBY
    end

    %w[upsert_all insert_all insert_all!].each do |method|
      it "prohíbe #{method} con filas que llevan status" do
        expect_offense(<<~RUBY, file, method:)
          Appointment.#{method}([ { id: id, status: "cancelled" } ])
          ^^^^^^^^^^^^{method}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message(method)}
        RUBY
      end
    end

    it "prohíbe update_attribute! del atributo status" do
      expect_offense(<<~RUBY, file)
        appointment.update_attribute!(:status, "no_show")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('update_attribute!')}
      RUBY
    end

    it "prohíbe la asignación directa status=" do
      expect_offense(<<~RUBY, file)
        appointment.status = "checked_in"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('status=')}
      RUBY
    end

    it "prohíbe también con navegación segura" do
      expect_offense(<<~RUBY, file)
        appointment&.update!(status: "cancelled")
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message('update!')}
      RUBY
    end

    it "permite escribir otras columnas y leer el estado", :aggregate_failures do
      expect_no_offenses(<<~RUBY, file)
        appointment.update!(notes: "x", lock_version: 2)
        Appointment.where(status: "scheduled").update_all(updated_at: now)
        appointment.update_column(:notes, "x")
        status = appointment.status
        appointment.attributes.slice("status")
      RUBY
    end
  end

  it "permite el archivo de Transition" do
    expect_no_offenses(<<~RUBY, "/app/packs/modules/appointments/app/public/appointments/transition.rb")
      Appointment.where(id: id, status: from).update_all("status = 'x'")
    RUBY
  end
end
