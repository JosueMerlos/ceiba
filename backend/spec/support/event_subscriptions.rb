# Aísla el registro de suscriptores entre ejemplos: cada ejemplo parte de los suscriptores reales (los de los packs) y
# lo que registre se descarta al terminar.
RSpec.configure do |config|
  config.around do |example|
    snapshot = Events::Subscriptions.all
    example.run
  ensure
    Events::Subscriptions.replace(snapshot)
  end
end
