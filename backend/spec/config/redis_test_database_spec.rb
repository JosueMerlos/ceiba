require "rails_helper"

# Los specs con Redis real hacen flushdb y destruyen el cron: jamás pueden compartir la base de Redis con desarrollo
# (compose da REDIS_URL=redis://redis:6379/0 a todos los contenedores, incluido el worker de desarrollo).
RSpec.describe "Base de Redis de test" do
  it "la URL de Redis en test es una base exclusiva (/15), no la de desarrollo" do
    expect(URI(Rails.configuration.x.redis_url).path).to eq("/15")
  end

  it "gana aunque REDIS_URL apunte a la base 0 (que es lo que da compose)" do
    expect(Sidekiq.redis { |connection| connection.call("CLIENT", "INFO") }).to include("db=15")
  end

  it "los specs :redis se niegan a limpiar una base que no sea la exclusiva de test", :redis do
    expect(Sidekiq.redis { |connection| connection.call("CLIENT", "INFO") }).to include("db=15")
  end
end
