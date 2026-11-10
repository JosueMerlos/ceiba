module Events
  class UnknownEvent < Error
    def initialize(name)
      super("El evento #{name.inspect} no tiene un esquema registrado: agrégalo en packs/<capa>/<pack>/app/public/<pack>/events/#{name}.json")
    end
  end
end
