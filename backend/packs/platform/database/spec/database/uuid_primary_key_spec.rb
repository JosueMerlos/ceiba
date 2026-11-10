require "rails_helper"

RSpec.describe "PK uuid por defecto", :tenant_schema do
  it "create_table con id: :uuid usa uuidv7()" do
    with_tenant_schema do |owner|
      owner.create_table(:foos, id: :uuid) { |t| t.string :name }

      expect(column_info(owner, :foos, :id)).to include("data_type" => "uuid", "column_default" => "uuidv7()")
    end
  end

  it "respeta un default explícito si se pide" do
    with_tenant_schema do |owner|
      owner.create_table(:foos, id: { type: :uuid, default: -> { "gen_random_uuid()" } })

      expect(column_info(owner, :foos, :id)["column_default"]).to eq("gen_random_uuid()")
    end
  end

  it "genera UUIDs v7 ordenados por tiempo" do
    with_tenant_schema do |owner|
      owner.create_table(:foos, id: :uuid)
      ids = Array.new(5) { owner.select_value("INSERT INTO foos DEFAULT VALUES RETURNING id") }

      expect(ids.map { |id| id[14] }.uniq).to eq([ "7" ])
      expect(ids).to eq(ids.sort)
    end
  end
end
