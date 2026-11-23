# The pilot's names and lookups, in their own module: a rake file's constants and methods otherwise land on Object.
module DemoAgendaPilot
  ORGANIZATION = "Piloto interno".freeze
  COMPANY_SLUG = "salon-piloto".freeze
  BRANCH = "Sucursal Piloto".freeze

  module_function

  # An interrupted run left the organization behind, so an existing one is reused and the idempotent steps complete it.
  def structure(owner)
    result = Tenancy::ProvisionOrganization.call(
      organization: { name: ORGANIZATION, legal_name: "#{ORGANIZATION}, S.A." },
      company: { name: "Salón Piloto", slug: COMPANY_SLUG, business_type: "salon", currency: "NIO" },
      branch: { name: BRANCH, time_zone: "America/Managua" }, extras: { owner: }
    )
    [ result.organization, result.company, result.branch ]
  rescue Tenancy::ProvisioningFailed => error
    raise unless error.code == :slug_taken

    organization = Tenancy::Directory.organizations_for(Access::Principal::User.new(owner).organization_ids).find_by!(name: ORGANIZATION)
    Tenancy.with_context(organization:) do
      company = Tenancy::Directory.companies.find_by!(slug: COMPANY_SLUG)
      [ organization, company, Tenancy::Directory.branches.find_by!(company_id: company.id, name: BRANCH) ]
    end
  end
end

namespace :demo do
  desc "Crea en desarrollo la organización Piloto interno: un salón con una semana de citas (idempotente; exige SEED_DEMO_PASSWORD)"
  task agenda_pilot: :environment do
    abort "demo:agenda_pilot solo corre en desarrollo" unless Rails.env.development?

    password = ENV.fetch("SEED_DEMO_PASSWORD") { abort "Falta SEED_DEMO_PASSWORD" }
    # The module's seeds are loaded by path: the root pack cannot see the module's constants.
    require Rails.root.join("packs/modules/appointments/db/pilot_seeds.rb")
    person = ->(email, full_name) { Identity::ProvisionUser.call(password:, email:, full_name:) }
    owner = person.call("duena@piloto-interno.ceiba.test", "Gabriela Duarte")
    receptionist = person.call("recepcion@piloto-interno.ceiba.test", "Julia Reyes")
    professional = person.call("profesional@piloto-interno.ceiba.test", "Rosa Martínez")

    organization, company, branch = DemoAgendaPilot.structure(owner)
    Tenancy.with_context(organization:, company:, branch:) do
      { receptionist => "receptionist", professional => "professional" }.each do |user, role_key|
        Access::GrantRole.call(user:, role_key:, organization:, company:, branch:)
      end
      Modules::Enable.call(company:, key: "appointments")
      created = AppointmentsPilotSeeds.seed(company:, branch:, professional_user_id: professional.id)
      puts(created ? "#{DemoAgendaPilot::ORGANIZATION} listo" : "Ya existe: #{DemoAgendaPilot::ORGANIZATION}")
    end
  end
end
