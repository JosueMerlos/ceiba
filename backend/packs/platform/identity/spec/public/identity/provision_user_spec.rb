require "rails_helper"

# Creating a user from code (seeds, console): idempotent by email. NOT the public sign-up nor an invitation: no endpoint
# exposes it.
RSpec.describe Identity::ProvisionUser do
  def call(**overrides)
    described_class.call(email: "ana@ceiba.test", full_name: "Ana Pérez", password: "contraseña-segura-1", **overrides)
  end

  it "crea el usuario y devuelve su principal" do
    principal = call

    expect(principal).to eq(Identity::Principal::User.new(id: Identity::User.find_by!(email: "ana@ceiba.test").id, email: "ana@ceiba.test", full_name: "Ana Pérez"))
  end

  it "la contraseña queda como digest y sirve para iniciar sesión" do
    call

    expect(Identity::Authenticate.call(email: "ana@ceiba.test", password: "contraseña-segura-1").token).to be_present
  end

  it "es idempotente: la segunda vez no duplica ni cambia la contraseña ni el nombre", :aggregate_failures do
    first = call
    second = call(password: "otra-contraseña-larga", full_name: "Otro Nombre")

    expect(second).to eq(first)
    expect(Identity::User.count).to eq(1)
    expect { Identity::Authenticate.call(email: "ana@ceiba.test", password: "contraseña-segura-1") }.not_to raise_error
  end

  it "reconoce el correo sin importar mayúsculas" do
    call

    expect { call(email: "ANA@ceiba.test") }.not_to change(Identity::User, :count)
  end

  it "rechaza una contraseña de menos de 12 caracteres" do
    expect { call(password: "corta") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
