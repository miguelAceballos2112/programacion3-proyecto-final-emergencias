// Conecta esta pestaña con su proceso LiveView en el servidor, por websocket.
// Phoenix y LiveView vienen como variables globales desde /vendor (sin herramientas
// de JavaScript).

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");

const Hooks = {
  // Mantiene la consola desplazada hasta la última respuesta
  Abajo: {
    mounted() { this.el.scrollTop = this.el.scrollHeight; },
    updated() { this.el.scrollTop = this.el.scrollHeight; }
  }
};

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});

// El servidor pide limpiar el campo de la consola después de ejecutar un comando
window.addEventListener("phx:limpiar-consola", () => {
  const entrada = document.querySelector("#form-consola input[name=linea]");
  if (entrada) { entrada.value = ""; entrada.focus(); }
});

liveSocket.connect();
window.liveSocket = liveSocket;
