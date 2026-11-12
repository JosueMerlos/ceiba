require "rails_helper"

# A missing key does not fail a request: I18n answers with "Translation missing" and the client receives that text as the
# message. These specs pin the keys the module's errors are looked up by.
RSpec.describe "Traducciones es-NI del módulo de citas" do
  around { |example| I18n.with_locale(:"es-NI") { example.run } }

  describe "errores de disponibilidad" do
    {
      "branch_id.inactive" => "la sucursal está inactiva",
      "branch_id.wrong_company" => "la sucursal no es de la empresa",
      "professional_id.inactive" => "el profesional está pausado o archivado",
      "professional_id.not_assigned" => "el profesional no está asignado a la sucursal",
      "professional_id.wrong_company" => "el profesional no es de la empresa",
      "service_ids.blank" => "indica al menos un servicio",
      "service_ids.too_many" => "se pueden pedir hasta 5 servicios a la vez",
      "service_ids.duplicated" => "hay servicios repetidos",
      "service_ids.inactive" => "algún servicio está inactivo o archivado",
      "service_ids.not_provided" => "el profesional no presta alguno de los servicios",
      "service_ids.multiple_resource_kinds" => "los servicios piden más de un tipo de recurso a la vez",
      "service_ids.wrong_company" => "algún servicio no es de la empresa",
      "from.too_early" => "`from` no puede ser anterior a ayer en la hora local de la sucursal"
    }.each do |key, message|
      it "`#{key}` se traduce a su mensaje" do
        expect(I18n.t("appointments.availability.errors.#{key}", raise: true)).to eq(message)
      end
    end

    it "`to.invalid_range` se traduce a un mensaje que habla del rango" do
      expect(I18n.t("appointments.availability.errors.to.invalid_range", raise: true)).to start_with("el rango debe ir de `from` a `to`")
    end

    it "el título del problema 422 está traducido" do
      expect(I18n.t("api.errors.appointments.availability_invalid", raise: true)).to eq("No se puede calcular la disponibilidad con esos datos")
    end
  end

  describe "validaciones de los modelos" do
    {
      "appointments/resource.attributes.base.archived" => "el recurso está archivado y no admite cambios",
      "appointments/weekly_schedule.attributes.base.overlap" => "la franja se solapa con otra del mismo dueño",
      "appointments/professional_service.attributes.service_id.archived" => "el servicio está archivado y no se puede vincular"
    }.each do |key, message|
      it "`#{key}` se traduce a su mensaje" do
        expect(I18n.t("activerecord.errors.models.#{key}", raise: true)).to eq(message)
      end
    end

    it "las franjas solapadas de un horario tienen mensaje" do
      expect(I18n.t("activemodel.errors.models.appointments/staff/replace_schedule/rejection.attributes.slots.overlap", raise: true))
        .to eq("hay franjas que se solapan")
    end
  end
end
