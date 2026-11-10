import Config

# Carpeta donde se guardan los archivos de texto plano. Cada ejecución de las
# pruebas usa una carpeta temporal nueva, para no mezclar sus datos con los del
# sistema ni con los de ejecuciones anteriores.
if config_env() == :test do
  config :emergencias,
    directorio_datos: Path.join(System.tmp_dir!(), "emergencias_test_#{System.os_time()}")
else
  config :emergencias, directorio_datos: "datos"
end
