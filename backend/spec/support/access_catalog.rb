# Catálogo de control de acceso (permisos y roles de sistema) sincronizado UNA vez al arrancar la suite. Son datos de
# plataforma (tablas globales), no de un ejemplo: los specs los usan igual que en producción tras `Access.sync!`.
# Los tests que prueban la sincronización la ejecutan dentro de la transacción del ejemplo (se revierte).
RSpec.configure do |config|
  config.before(:suite) { Access.sync! }
end
