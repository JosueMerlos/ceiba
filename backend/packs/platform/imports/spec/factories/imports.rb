FactoryBot.define do
  # Used INSIDE a tenant. Only ids are stored (no associations to the private Tenancy models), so the branch is a transient
  # and organization_id always comes from it.
  factory :import_batch, class: "Imports::Batch" do
    transient { branch { association(:branch, strategy: :create) } }

    company_id { branch.company_id }
    branch_id { branch.id }
    organization { branch.organization }
    kind { "customers" }
    created_by_id { SecureRandom.uuid_v7 }
    expires_at { Imports::Batch::PREVIEW_TTL.from_now }
  end

  factory :import_row, class: "Imports::Row" do
    batch { association(:import_batch, strategy: :create) }
    organization { batch.organization }
    sequence(:row_number) { |n| n + 1 }
    status { "ready" }
    payload { { "nombre" => "Ana", "telefono" => "8800 0001" }.to_json }
  end
end
