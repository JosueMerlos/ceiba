Rails.application.config.to_prepare do
  Imports::Registry.register("services", importer: "Appointments::Imports::ServicesImporter",
                                          policy: "Appointments::ServiceImportPolicy", module_key: :appointments)
  Imports::Registry.register("professionals", importer: "Appointments::Imports::ProfessionalsImporter",
                                               policy: "Appointments::ProfessionalImportPolicy", module_key: :appointments)
end
