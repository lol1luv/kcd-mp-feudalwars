// Command menu. from the mode: KcdMp.onMessage({commands: [{cmd, desc}]})
//   to the mode: menu.close, menu.run {cmd}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const tbody = document.querySelector("#cmds tbody");
    tbody.replaceChildren();
    for (const c of data.commands || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = c.cmd;
      const td2 = document.createElement("td"); td2.textContent = c.desc;
      const td3 = document.createElement("td");
      const b = document.createElement("button");
      b.className = "act";
      b.textContent = "Run";
      b.addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: c.cmd }));
      td3.append(b);
      tr.append(td1, td2, td3);
      tbody.append(tr);
    }
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("menu.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("menu.close"); });
  $("go-me").addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: "/me" }));
  $("go-hall").addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: "/hall" }));
  $("go-admin").addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: "/admin" }));
})();
