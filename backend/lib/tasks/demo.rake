namespace :demo do
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

    begin
      result = Tenancy::ProvisionOrganization.call(
        organization: { name: "Piloto interno", legal_name: "Piloto interno, S.A." },
        company: { name: "Salón Piloto", slug: "salon-piloto", business_type: "salon", currency: "NIO" },
        branch: { name: "Sucursal Piloto", time_zone: "America/Managua" }, extras: { owner: }
      )
    rescue Tenancy::ProvisioningFailed => error
      raise unless error.code == :slug_taken

      next puts("Ya existe: Piloto interno")
    end

    Tenancy.with_context(organization: result.organization, company: result.company, branch: result.branch) do
      { receptionist => "receptionist", professional => "professional" }.each do |user, role_key|
        Access::GrantRole.call(user:, role_key:, organization: result.organization, company: result.company, branch: result.branch)
      end
      Modules::Enable.call(company: result.company, key: "appointments")
      AppointmentsPilotSeeds.seed(company: result.company, branch: result.branch, professional_user_id: professional.id)
    end
    puts "Piloto interno listo"
  end
end
