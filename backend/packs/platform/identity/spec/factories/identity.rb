FactoryBot.define do
  factory :user, class: "Identity::User" do
    sequence(:email) { |n| "usuario#{n}@ceiba.test" }
    full_name { "Ana Pérez" }
    password { "contraseña-segura-1" }
  end
end
