# Las pruebas marcadas con :personas usan Emergencias.Personas (Integrante 3).
# Mientras ese módulo no esté en el proyecto, se omiten.
excluir = if Code.ensure_loaded?(Emergencias.Personas), do: [], else: [:personas]

ExUnit.start(exclude: excluir)
