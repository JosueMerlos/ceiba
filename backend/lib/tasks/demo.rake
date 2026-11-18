namespace :demo do
  PILOT_ORGANIZATION = "Piloto interno".freeze
  PILOT_COMPANY_SLUG = "salon-piloto".freeze
  PILOT_BRANCH = "Sucursal Piloto".freeze

  desc "Crea en desarrollo la organización Piloto interno: un salón con una semana de citas (idempotente; exige SEED_DEMO_PASSWORD)"
  task agenda_pilot: :environment do
    abort "demo:agenda_pilot solo corre en desarrollo" unless Rails.env.development?

    password = ENV.fetch("SEED_DEMO_PASSWORD") { abort "Falta SEED_DEMO_PASSWORD" }
    # The module's seeds are loaded by path: the root pack cannot see the module's constants.
    require Rails.root.join("packs/modules/appointments/db/pilot_seeds.rb")
    person = ->(email, full_name) { Identity::ProvisionUser.call(password:, email:, full_name:) }
    owner = person.call("duena@piloto-interno.ceiba.test", "Rosa Martínez")
    receptionist = person.call("recepcion@piloto-interno.ceiba.test", "Julia Reyes")
    professional = person.call("profesional@piloto-interno.ceiba.test", "Rosa Martínez")

    organization, company, branch = pilot_structure(owner)
    Tenancy.with_context(organization:, company:, branch:) do
      { receptionist => "receptionist", professional => "professional" }.each do |user, role_key|
        Access::GrantRole.call(user:, role_key:, organization:, company:, branch:)
      end
      Modules::Enable.call(company:, key: "appointments")
      created = AppointmentsPilotSeeds.seed(company:, branch:, professional_user_id: professional.id)
      puts(created ? "Piloto interno listo" : "Ya existe: Piloto interno")
    end
  end

  # An interrupted run left the organization behind, so an existing one is reused and the idempotent steps complete it.
  def pilot_structure(owner)
    result = Tenancy::ProvisionOrganization.call(
      organization: { name: PILOT_ORGANIZATION, legal_name: "#{PILOT_ORGANIZATION}, S.A." },
      company: { name: "Salón Piloto", slug: PILOT_COMPANY_SLUG, business_type: "salon", currency: "NIO" },
      branch: { name: PILOT_BRANCH, time_zone: "America/Managua" }, extras: { owner: }
    )
    [ result.organization, result.company, result.branch ]
  rescue Tenancy::ProvisioningFailed => error
    raise unless error.code == :slug_taken

    organization = Tenancy::Directory.organizations_for(Access::Principal::User.new(owner).organization_ids).find_by!(name: PILOT_ORGANIZATION)
    Tenancy.with_context(organization:) do
      company = Tenancy::Directory.companies.find_by!(slug: PILOT_COMPANY_SLUG)
      [ organization, company, Tenancy::Directory.branches.find_by!(company_id: company.id, name: PILOT_BRANCH) ]
    end
  end
end
