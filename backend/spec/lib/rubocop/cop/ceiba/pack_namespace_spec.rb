require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/pack_namespace"

RSpec.describe RuboCop::Cop::Ceiba::PackNamespace, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) { { "Include" => [ "packs/*/*/app/**/*.rb" ] } }

  context "con un archivo dentro de app/ de un pack" do
    it "acepta el módulo con el namespace del pack" do
      expect_no_offenses(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        module Appointments
          class Booking < ApplicationRecord
          end
        end
      RUBY
    end

    it "acepta la forma compacta Pack::Clase" do
      expect_no_offenses(<<~RUBY, "packs/platform/tenancy/app/services/tenancy/provision.rb")
        class Tenancy::Provision
        end
      RUBY
    end

    it "acepta un namespace anidado que empieza por el del pack" do
      expect_no_offenses(<<~RUBY, "packs/platform/access/app/policies/access/roles/policy.rb")
        module Access
          module Roles
            class Policy; end
          end
        end
      RUBY
    end

    it "acepta el namespace del pack en snake_case camelizado" do
      expect_no_offenses(<<~RUBY, "packs/platform/bar_baz/app/public/bar_baz/api.rb")
        module BarBaz
          class Api; end
        end
      RUBY
    end

    it "acepta Api::V1::Pack en los controladores" do
      expect_no_offenses(<<~RUBY, "packs/modules/appointments/app/controllers/api/v1/appointments/bookings_controller.rb")
        module Api
          module V1
            module Appointments
              class BookingsController < ApplicationController; end
            end
          end
        end
      RUBY
    end

    it "rechaza el namespace de otro pack" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        module Billing
               ^^^^^^^ El namespace debe empezar por `Appointments` (pack packs/modules/appointments).
          class Booking; end
        end
      RUBY
    end

    it "rechaza una clase sin namespace" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        class Booking < ApplicationRecord
              ^^^^^^^ El namespace debe empezar por `Appointments` (pack packs/modules/appointments).
        end
      RUBY
    end

    it "rechaza un nombre que solo comparte prefijo de texto" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        module AppointmentsExtra
               ^^^^^^^^^^^^^^^^^ El namespace debe empezar por `Appointments` (pack packs/modules/appointments).
        end
      RUBY
    end

    it "rechaza Api::V1::Pack fuera de los controladores" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/models/api/v1/appointments/booking.rb")
        module Api
               ^^^ El namespace debe empezar por `Appointments` (pack packs/modules/appointments).
          module V1; end
        end
      RUBY
    end

    it "revisa todas las definiciones del nivel superior" do
      expect_offense(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        module Appointments; end
        class Stray; end
              ^^^^^ El namespace debe empezar por `Appointments` (pack packs/modules/appointments).
      RUBY
    end

    it "rechaza un módulo hermano de otro pack dentro de Api::V1 en los controladores" do
      expect_offense(<<~RUBY, "packs/modules/example_other/app/controllers/api/v1/example_other/things_controller.rb")
        module Api
          module V1
            module ExampleOther
              class ThingsController; end
            end
            module Billing
                   ^^^^^^^ El namespace debe empezar por `ExampleOther` (pack packs/modules/example_other).
              class Hack; end
            end
          end
        end
      RUBY
    end

    it "trata `::` como absoluto: no hereda el namespace que lo envuelve" do
      expect_offense(<<~RUBY, "packs/modules/example_other/app/models/example_other/thing.rb")
        module ExampleOther
          class ::ExampleModule::Sneaky; end
                ^^^^^^^^^^^^^^^^^^^^^^^ El namespace debe empezar por `ExampleOther` (pack packs/modules/example_other).
        end
      RUBY
    end

    it "acepta una constante absoluta dentro del namespace del pack" do
      expect_no_offenses(<<~RUBY, "packs/modules/example_other/app/models/example_other/thing.rb")
        class ::ExampleOther::Thing; end
      RUBY
    end

    it "rechaza una clase de otro namespace anidada dentro del pack" do
      expect_offense(<<~RUBY, "packs/modules/example_other/app/models/example_other/thing.rb")
        module ExampleOther
          module Nested
            class ::Billing::Hack; end
                  ^^^^^^^^^^^^^^^ El namespace debe empezar por `ExampleOther` (pack packs/modules/example_other).
          end
        end
      RUBY
    end

    it "ignora el código que no define constantes" do
      expect_no_offenses(<<~RUBY, "packs/modules/appointments/app/models/appointments/booking.rb")
        Appointments::Booking = Struct.new(:id)
      RUBY
    end
  end

  context "con un archivo fuera de app/ de un pack" do
    it "no revisa el código de la raíz de Rails" do
      expect_no_offenses(<<~RUBY, "app/models/application_record.rb")
        class ApplicationRecord < ActiveRecord::Base; end
      RUBY
    end
  end
end
