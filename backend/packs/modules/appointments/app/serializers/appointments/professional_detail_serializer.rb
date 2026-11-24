module Appointments
  # Fields match components.schemas.ProfessionalDetail EXACTLY: the professional plus their contact. The contact is personal
  # data, so it is null unless the caller built the serializer with `params: { contact: true }` (the reader may manage
  # professionals). Lists and branch views use ProfessionalSerializer, which has no contact keys at all.
  class ProfessionalDetailSerializer < ProfessionalSerializer
    attribute(:phone) { |professional| params[:contact] ? professional.phone_e164 : nil }
    attribute(:email) { |professional| params[:contact] ? professional.email : nil }
  end
end
