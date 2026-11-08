namespace :openapi do
  desc "Genera openapi/v1.yaml (claves ordenadas) a partir de los specs de rswag. Corre en el entorno test."
  task :generate do
    specs = Dir.glob("{spec,packs/*/*/spec}/api/**/*_spec.rb").sort
    abort "openapi:generate: no hay specs de rswag (spec/api, packs/*/*/spec/api)" if specs.empty?

    # Se lanza un rspec aparte: los specs necesitan RAILS_ENV=test (la tarea suele correr en development) y el
    # formateador solo registra la documentación (--dry-run), no ejecuta las peticiones.
    env = { "RAILS_ENV" => "test" }
    command = [ "bundle", "exec", "rspec", "--require", "swagger_helper", "--require", "openapi/formatter", "--format", "Openapi::Formatter", "--dry-run", "--order", "defined", *specs ]
    system(env, *command) || abort("openapi:generate: falló rspec")
  end
end
