module Identity
  # Alta de un usuario por código (seeds, consola). Idempotente por correo: si ya existe se devuelve tal cual, SIN tocar
  # su contraseña ni su nombre (un seed repetido no debe pisar lo que el usuario cambió).
  #
  # No es el registro público ni la invitación (M4.01); ningún endpoint lo expone.
  #
  #   Identity::ProvisionUser.call(email: "ana@ceiba.test", full_name: "Ana Pérez", password: "…12 o más caracteres…")
  #   # => Identity::Principal::User
  module ProvisionUser
    def self.call(email:, full_name:, password:)
      user = User.find_by(email:) || create(email:, full_name:, password:)
      Principal::User.new(id: user.id, email: user.email, full_name: user.full_name)
    end

    # Dos seeds simultáneos: gana el índice único y el perdedor lee la fila del ganador.
    def self.create(email:, full_name:, password:)
      User.create!(email:, full_name:, password:)
    rescue ActiveRecord::RecordNotUnique
      User.find_by!(email:)
    end
    private_class_method :create
  end
end
