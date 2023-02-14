let team_0_color = "black";
let team_1_color = "black";

window.addEventListener("load", function(){
  let es = new EventSource("mobius/stream");
  let chat_log = document.querySelector("#chat_log")

  es.onmessage = (e) => {
    handle_payload(JSON.parse(e.data));
    // const element = document.createElement("p")
    // element.textContent = e.data

    // chat_log.appendChild(element)
  }

  es.onerror = (e) => {
    const element = document.createElement("p")
    element.textContent = e.data

    chat_log.appendChild(element)
  }

  let chat_form = document.querySelector("#chat_form")
  let chat_message = document.querySelector("#chat_message")
  chat_form.addEventListener("submit", function(e) {
    e.preventDefault();
    e.stopPropagation();

    if (chat_message.value.length <= 0)
    {
      return;
    }

    let data = {}
    data.type = "chat"
    data.message = chat_message.value

    post_data(chat_form.action, data).then((response) => {
      console.log(response);

      if (response.status == 200) {
        let element = document.createElement("p")
        element.textContent = chat_message.value;
        chat_message.value = "";

        add_element_and_scroll_to_end(chat_log, element);
      }
    });
  });
})

async function post_data(url = '', data = {}) {
  const response = await fetch(url, {
    method: "POST",
    mode: "same-origin",
    cache: "no-cache",
    headers: {
      "Content-Type": "application/json"
    },
    credentials: "same-origin",
    redirect: "follow",
    referrerPolicy: "no-referrer",
    body: JSON.stringify(data)
  });

  return response;
}

function handle_payload(data = {}) {
  console.log(data.type);

  switch(data.type) {
    case "keep_alive":
      // NO-OP: Ensure socket stays connected
      break;
    case "full_payload":
      // TODO: Update map name
      // TODO: Update team lists
      console.log(data);
      update_teams_list(data);
      break;
    case "chat":
    case "team_chat":
      send_message_to_chat_log(data);
      break;
    case "log":
      send_log_to_chat_log(data);
      break;
    case "fds":
      // TODO: Append to fds log
      break;
    default:
      console.log("UNHANDLED PAYLOAD:");
      console.log(data);
  }
}

function scrolled_to_bottom(e) {
  return e.scrollHeight - e.scrollTop == e.offsetHeight;
}

function add_element_and_scroll_to_end(chat_log, element) {
  let at_bottom = scrolled_to_bottom(chat_log);

  chat_log.appendChild(element);

  if (at_bottom) {
    chat_log.scrollTop = chat_log.scrollHeight;
  }
}

function send_log_to_chat_log(payload) {
  let element = document.createElement("p");
  element.innerHTML = payload.message;

  add_element_and_scroll_to_end(chat_log, element);
}

function send_message_to_chat_log(payload) {
  let element = document.createElement("p");
  if (payload.type == "team_chat") {
    element.style.color = (payload.team == 0 ? team_0_color : team_1_color);
    element.innerHTML = "<b>" + payload.player + ":</b> " + payload.message;
  } else {
    element.innerHTML = "<b style='color: " + (payload.team == 0 ? team_0_color : team_1_color) + "'>" + payload.player + ":</b> " + payload.message;
  }

  add_element_and_scroll_to_end(chat_log, element);
}

function send_message_to_fds_log(payload) {
  let element = document.createElement("p");
  element.textContent = payload.message;

  add_element_and_scroll_to_end(fds_log, element);
}

function update_teams_list(data) {
  let team_name_element;
  let team_0_list_element = document.querySelector("#team_box_0 .team_list");
  let team_1_list_element = document.querySelector("#team_box_1 .team_list");

  data.teams.forEach(team => {
    switch(team.id) {
      case 0:
        team_name_element = document.querySelector("#team_0_name");
        team_name_element.textContent = team.name;
        team_name_element.style.background = "#" + team.color;
        team_0_color = "#" + team.color;
        break;

      case 1:
        team_name_element = document.querySelector("#team_1_name");
        team_name_element.textContent = team.name;
        team_name_element.style.background = "#" + team.color;
        team_1_color = "#" + team.color;
        break;
    }
  });

  team_0_list_element.innerHTML = "";
  team_1_list_element.innerHTML = "";

  let team_0_players = data.players.filter(function(player) { return player.team == 0; } );
  let team_1_players = data.players.filter(function(player) { return player.team == 1; } );

  team_0_players.forEach(player => {
    let element = document.createElement("p")
    element.textContent = "" + player.id + ". " + player.name;

    team_0_list_element.appendChild(element);
  });

  team_1_players.forEach(player => {
    let element = document.createElement("p")
    element.textContent = "" + player.id + ". " + player.name;

    team_1_list_element.appendChild(element);
  });
}