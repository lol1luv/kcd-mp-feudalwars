// Main menu (hub). from the mode: KcdMp.onMessage({commands: [{cmd, title, desc}], lang, title, keys, ...})
//   to the mode: menu.close, menu.run {cmd}, menu.cursor, menu.lang {lang}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);

  function show(which) {
    $("panel-main").hidden = which !== "main";
    $("panel-settings").hidden = which !== "settings";
  }

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    $("title").textContent = data.title || "Feudal Wars";
    $("keys").textContent = data.keys || "";
    $("mouse-text").textContent = data.mouse || "";
    $("cursor").textContent = data.btn_mouse || "";
    $("go-me").textContent = data.btn_me || "";
    $("go-hall").textContent = data.btn_hall || "";
    $("go-admin").textContent = data.btn_admin || "";
    $("go-settings").textContent = data.btn_settings || "";
    $("th-cmd").textContent = data.col_cmd || "";
    $("th-what").textContent = data.col_what || "";
    $("settings-title").textContent = data.settings_title || "";
    $("settings-lang-label").textContent = data.settings_lang || "";
    $("settings-back").textContent = data.settings_back || "";
    const tbody = document.querySelector("#cmds tbody");
    tbody.replaceChildren();
    for (const c of data.commands || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td");
      const b = document.createElement("b"); b.textContent = c.title || c.cmd;
      const small = document.createElement("div"); small.className = "cmd"; small.textContent = c.cmd;
      td1.append(b, small);
      const td2 = document.createElement("td"); td2.textContent = c.desc;
      const td3 = document.createElement("td");
      const btn = document.createElement("button");
      btn.className = "act";
      btn.textContent = data.btn_open || "Open";
      btn.addEventListener("click", () => KcdMp.emitServer("menu.run", { action: c.action || c.cmd, cmd: c.cmd }));
      td3.append(btn);
      tr.append(td1, td2, td3);
      tbody.append(tr);
    }
    show("main");
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("menu.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("menu.close"); });
  $("cursor").addEventListener("click", () => KcdMp.emitServer("menu.cursor"));
  $("go-me").addEventListener("click", () => KcdMp.emitServer("menu.run", { action: "me" }));
  $("go-hall").addEventListener("click", () => KcdMp.emitServer("menu.run", { action: "hall" }));
  $("go-admin").addEventListener("click", () => KcdMp.emitServer("menu.run", { action: "admin" }));
  $("go-settings").addEventListener("click", () => show("settings"));
  $("settings-back").addEventListener("click", () => show("main"));
  $("lang-en").addEventListener("click", () => KcdMp.emitServer("menu.lang", { lang: "en" }));
  $("lang-ru").addEventListener("click", () => KcdMp.emitServer("menu.lang", { lang: "ru" }));
})();
