window.addEventListener("load", function(){
  let es = new EventSource("mobius/stream");
  let chat_log = document.querySelector("#chat_log")

  es.onmessage = (e) => {
    const element = document.createElement("p")
    element.textContent = e.data

    chat_log.appendChild(element)
  }

  es.onerror = (e) => {
    const element = document.createElement("p")
    element.textContent = e.data

    chat_log.appendChild(element)
  }
})