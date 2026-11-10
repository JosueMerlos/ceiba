# Isolates the subscriber registry between examples: each example starts from the real subscribers (the packs') and
# whatever it registers is discarded afterwards.
RSpec.configure do |config|
  config.around do |example|
    snapshot = Events::Subscriptions.all
    example.run
  ensure
    Events::Subscriptions.replace(snapshot)
  end
end
