import Config

# Servidor web: http://localhost:4000
config :emergencias_web, EmergenciasWeb.Endpoint,
  url: [host: "localhost"],
  # El websocket de LiveView acepta el mismo host por el que se abrió la página
  # (localhost, 127.0.0.1 o la IP del equipo en la red)
  check_origin: :conn,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  # Llaves para firmar las cookies de sesión. En un sistema real irían en una variable
  # de entorno; para el proyecto basta con estas.
  secret_key_base: "Wm8kq3Vt0sXc5Ld9Pz2Hn7Rb4Jf6Ga1Qy8Ue3Ko0Mw5Ti2Ap7Sd9Fg4Hj6Kl1Zx3Cv",
  live_view: [signing_salt: "emergencias-lv"],
  pubsub_server: EmergenciasWeb.PubSub,
  render_errors: [formats: [html: EmergenciasWeb.ErrorHTML], layout: false]

config :phoenix, :json_library, Jason

config :logger, :default_formatter, format: "$time [$level] $message\n"

if config_env() == :test do
  # Las pruebas usan otro puerto, no levantan el servidor HTTP y guardan sus datos en
  # una carpeta temporal nueva
  config :emergencias_web, EmergenciasWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 4002],
    server: false

  config :emergencias,
    directorio_datos: Path.join(System.tmp_dir!(), "emergencias_web_test_#{System.os_time()}")

  config :logger, level: :warning
else
  # La web y la consola comparten la carpeta datos/ de la raíz del proyecto (o la que
  # indique la variable de entorno EMERGENCIAS_DATOS).
  # No abra la consola local y la web al mismo tiempo: serían dos sistemas distintos
  # escribiendo los mismos archivos. Use la consola remota (ver el README).
  config :emergencias,
    directorio_datos: System.get_env("EMERGENCIAS_DATOS") || Path.expand("../../datos", __DIR__)
end
