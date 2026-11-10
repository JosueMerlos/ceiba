require "rails_helper"

# `rails g model Foo` + migrate => foos.id is uuid with default uuidv7().
RSpec.describe "rails g model con las convenciones de BD" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_generator_probe").create }

  after { app.destroy }

  def column(table, name)
    app.rails_runner(<<~RUBY)
      row = ActiveRecord::Base.connection.select_one("SELECT data_type, column_default FROM information_schema.columns WHERE table_name = '#{table}' AND column_name = '#{name}'")
      puts row.values.join("|")
    RUBY
  end

  before do
    app.run!("bin/rails", "g", "model", "Foo", "name:string", "--no-test-framework")
    app.run!("bin/rails", "g", "model", "Bar", "foo:references", "--no-test-framework")
    app.db!("db:create", "db:migrate")
  end

  it "crea foos.id como uuid con default uuidv7()" do
    expect(column("foos", "id")).to eq("uuid|uuidv7()")
  end

  it "crea las referencias como uuid" do
    expect(column("bars", "foo_id")).to eq("uuid|")
  end

  it "genera IDs UUIDv7 al insertar" do
    id = app.rails_runner("puts ActiveRecord::Base.connection.select_value(\"INSERT INTO foos (name, created_at, updated_at) VALUES ('x', now(), now()) RETURNING id\")")

    expect(id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "usa db/structure.sql y no genera db/schema.rb" do
    expect(app.exist?("db/structure.sql")).to be(true)
    expect(app.exist?("db/schema.rb")).to be(false)
  end
end
