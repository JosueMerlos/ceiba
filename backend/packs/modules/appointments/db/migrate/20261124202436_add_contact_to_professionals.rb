# How to reach a professional: phone (E.164) and email. Both are encrypted by the model (deterministic ciphertext), so the
# columns hold ciphertext and stay NULL until someone types them.
class AddContactToProfessionals < ActiveRecord::Migration[8.1]
  def change
    add_column :professionals, :phone_e164, :string
    add_column :professionals, :email, :string
  end
end
