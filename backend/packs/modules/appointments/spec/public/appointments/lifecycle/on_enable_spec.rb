require "rails_helper"

RSpec.describe Appointments::Lifecycle::OnEnable do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def enable(target = company) = with_tenant(organization) { Modules::Enable.call(company: target, key: "appointments") }
  def disable(target = company) = with_tenant(organization) { Modules::Disable.call(company: target, key: "appointments") }

  def branch_hours(branch, in_organization: organization)
    with_tenant(in_organization) do
      Appointments::WeeklySchedule.where(branch_id: branch.id, owner_type: "branch").order(:weekday, :starts_at_local)
                                  .map { [ it.weekday, it.starts_at_local.strftime("%H:%M"), it.ends_at_local.strftime("%H:%M") ] }
    end
  end

  def default_hours = (1..6).map { [ it, "08:00", "18:00" ] }

  it "una empresa aprovisionada con el módulo tiene su sucursal con lunes a sábado de 08:00 a 18:00 (CA 5)", :aggregate_failures do
    result = Tenancy::ProvisionOrganization.call(
      organization: { name: "Org #{SecureRandom.hex(3)}" },
      company: { name: "Barbería", slug: "barberia-#{SecureRandom.hex(3)}", business_type: "barbershop", currency: "NIO" },
      branch: { name: "Central", time_zone: "America/Managua" }
    )

    expect(branch_hours(result.branch, in_organization: result.organization)).to eq(default_hours)
    expect(with_tenant(result.organization) { Appointments::WeeklySchedule.count }).to eq(6)
  end

  it "al activar el módulo en una empresa con dos sucursales, ambas reciben el horario por defecto", :aggregate_failures do
    first = create_in(organization, :branch, company:)
    second = create_in(organization, :branch, company:)

    enable

    expect(branch_hours(first)).to eq(default_hours)
    expect(branch_hours(second)).to eq(default_hours)
  end

  it "audita una vez por sucursal, sin guardar nada personal", :aggregate_failures do
    branch = create_in(organization, :branch, company:)

    enable

    event = with_tenant(organization) { Audit::Event.where(action: "schedule.defaults_created").sole }
    expect(event).to have_attributes(auditable_id: branch.id, metadata: include("branch_id" => branch.id, "company_id" => company.id))
    expect(event.after["slots"].size).to eq(6)
  end

  it "desactivar y reactivar deja intacto un horario editado y no duplica nada", :aggregate_failures do
    branch = create_in(organization, :branch, company:)
    other = create_in(organization, :branch, company:)
    enable
    with_tenant(organization) do
      Appointments::Staff::ReplaceSchedule.call(owner: branch, branch_id: branch.id, slots: [ { weekday: 2, starts_at_local: "10:00", ends_at_local: "14:00" } ])
    end

    disable
    enable

    expect(branch_hours(branch)).to eq([ [ 2, "10:00", "14:00" ] ])
    expect(branch_hours(other)).to eq(default_hours)
    expect(with_tenant(organization) { Audit::Event.where(action: "schedule.defaults_created").count }).to eq(2)
  end

  it "una sucursal cerrada a propósito (franjas vacías) sigue cerrada tras desactivar y reactivar", :aggregate_failures do
    branch = create_in(organization, :branch, company:)
    enable
    with_tenant(organization) { Appointments::Staff::ReplaceSchedule.call(owner: branch, branch_id: branch.id, slots: []) }

    disable
    enable

    expect(branch_hours(branch)).to be_empty
    expect(with_tenant(organization) { Audit::Event.where(action: "schedule.defaults_created").count }).to eq(1)
  end

  it "una sucursal sin horario de sucursal lo recibe aunque tenga horarios de profesionales o recursos" do
    branch = create_in(organization, :branch, company:)
    with_tenant(organization) do
      professional = create(:professional, company:)
      create(:professional_branch_assignment, professional:, branch:)
      create(:weekly_schedule, branch:, professional:)
    end

    enable

    expect(branch_hours(branch)).to eq(default_hours)
  end

  it "no toca las sucursales de otra empresa de la misma organización" do
    other_company = create_in(organization, :company)
    foreign = create_in(organization, :branch, company: other_company)
    create_in(organization, :branch, company:)

    enable

    expect(branch_hours(foreign)).to be_empty
  end

  it "una empresa sin sucursales se activa sin crear nada" do
    enable

    expect(with_tenant(organization) { Appointments::WeeklySchedule.count }).to eq(0)
  end
end
