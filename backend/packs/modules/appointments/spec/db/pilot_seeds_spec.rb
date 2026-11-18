require "rails_helper"

# The simulated salon week behind the internal pilot and the agenda's load measurement.
RSpec.describe "Datos del piloto interno de la agenda" do # rubocop:disable RSpec/DescribeClass
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:branch) { world.branch_a1 }
  let(:company) { world.company_a }
  let(:user) { user_with_role("professional", world, branch: world.branch_a1) }
  # Wednesday 18 Nov 2026, 11:30 in America/Managua (UTC-6).
  let(:now) { Time.utc(2026, 11, 18, 17, 30) }

  before do
    require Rails.root.join("packs/modules/appointments/db/pilot_seeds.rb")
    travel_to now
    with_tenant(world.organization) do
      Modules::Enable.call(company:, key: "appointments")
      AppointmentsPilotSeeds.seed(company:, branch:, professional_user_id: user.id)
    end
  end

  after { travel_back }

  def local_day(appointment) = appointment.starts_at.in_time_zone(branch.time_zone).to_date

  def appointments = Appointments::Appointment.where(branch_id: branch.id)

  it "deja 5 profesionales con horario y al menos 40 citas activas hoy", :aggregate_failures do
    with_tenant(world.organization) do
      today = appointments.to_a.select { local_day(it) == Date.new(2026, 11, 18) }

      expect(Appointments::Professional.assigned_to(branch).count).to eq(5)
      expect(today.count { it.status != "cancelled" }).to be >= 40
      expect(today.map(&:professional_id).uniq.size).to eq(5)
    end
  end

  it "cubre la semana de lunes a sábado con estados coherentes con el reloj", :aggregate_failures do
    with_tenant(world.organization) do
      rows = appointments.to_a
      past, future = rows.partition { it.starts_at < now }

      expect(rows.map { local_day(it) }.uniq.sort).to eq((Date.new(2026, 11, 16)..Date.new(2026, 11, 21)).to_a)
      expect(past.map(&:status).uniq).to include("completed", "no_show", "cancelled")
      expect(future.map(&:status).uniq).to contain_exactly("scheduled", "confirmed")
    end
  end

  it "vincula al primer profesional con el usuario indicado" do
    with_tenant(world.organization) do
      expect(Appointments::Professional.of_user(user.id, branch:).count).to eq(1)
    end
  end

  describe "si la siembra falla a mitad" do
    def other_company = world.company_b
    def other_branch = world.branch_b1

    def seed_other = AppointmentsPilotSeeds.seed(company: other_company, branch: other_branch, professional_user_id: nil)

    it "no deja nada a medias y la siguiente corrida la completa", :aggregate_failures do
      with_tenant(world.organization) do
        Modules::Enable.call(company: other_company, key: "appointments")
        allow(AppointmentsPilotSeeds).to receive(:book_week).and_raise(ActiveRecord::RecordInvalid)

        expect { seed_other }.to raise_error(ActiveRecord::RecordInvalid)
        expect(Appointments::Service.where(company_id: other_company.id)).not_to exist

        allow(AppointmentsPilotSeeds).to receive(:book_week).and_call_original
        expect(seed_other).to be(true)
        expect(Appointments::Appointment.where(branch_id: other_branch.id)).to exist
      end
    end
  end

  it "una segunda corrida no duplica nada" do
    with_tenant(world.organization) do
      expect { AppointmentsPilotSeeds.seed(company:, branch:, professional_user_id: user.id) }.not_to change(appointments, :count)
    end
  end
end
