Rails.application.config.to_prepare do
  Imports::Registry.register("customers", importer: "Customers::Importer", policy: "Customers::ImportPolicy")
end
