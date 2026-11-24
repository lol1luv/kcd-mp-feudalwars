// The house hall.  from the mode: KcdMp.onMessage({name, house, treasury, prestige, members: [{name, rank, online}], wars: [{enemy, score, since}], canWar})
//   to the mode: house.close, house.promote {name}, house.demote {name}, house.kick {name}, house.donate {amount},
//                house.prestige, house.declare {enemy}, house.peace {enemy}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  let state = null;

  function show(tab) {
    for (const b of document.querySelectorAll("#tabs button")) b.setAttribute("aria-selected", String(b.dataset.tab === tab));
    for (const p of document.querySelectorAll("[data-panel]")) p.hidden = p.dataset.panel !== tab;
  }
  for (const b of document.querySelectorAll("#tabs button")) b.addEventListener("click", () => show(b.dataset.tab));

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    state = data;

    $("title").textContent = "The House of " + (data.house || "?");

    const tbody = document.querySelector("#members tbody");
    tbody.replaceChildren();
    for (const m of data.members || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = m.name;
      const td2 = document.createElement("td");
      const badge = document.createElement("span"); badge.className = "badge"; badge.textContent = m.rank;
      td2.append(badge);
      const td3 = document.createElement("td"); td3.textContent = m.online ? "in the realm" : "away";
      if (m.online) tr.className = "online";
      tr.append(td1, td2, td3);
      tbody.append(tr);
    }

    const purse = $("purse");
    purse.replaceChildren();
    const row = (term, value) => {
      const dt = document.createElement("dt"); dt.textContent = term;
      const dd = document.createElement("dd"); dd.textContent = value;
      purse.append(dt, dd);
    };
    row("Treasury", Number(data.treasury || 0).toLocaleString() + " groschen");
    row("Prestige", "level " + Number(data.prestige || 1));
    row("Your purse", Number(data.money || 0).toLocaleString() + " groschen");

    const wbody = document.querySelector("#warlist tbody");
    wbody.replaceChildren();
    for (const w of data.wars || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = "the house of " + w.enemy;
      const td2 = document.createElement("td");
      const badge = document.createElement("span"); badge.className = "badge war"; badge.textContent = String(w.score);
      td2.append(badge);
      const td3 = document.createElement("td"); td3.textContent = w.since;
      tr.append(td1, td2, td3);
      wbody.append(tr);
    }
  });

  const emit = (name, payload) => KcdMp.emitServer(name, payload || {});

  $("close").addEventListener("click", () => emit("house.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") emit("house.close"); });
  $("donate").addEventListener("click", () => emit("house.donate", { amount: 100 }));
  $("prestige").addEventListener("click", () => emit("house.prestige"));
  $("declare").addEventListener("click", () => emit("house.declare", { enemy: $("enemyName").value.trim() }));
  $("peace").addEventListener("click", () => emit("house.peace"));
  $("promote").addEventListener("click", () => emit("house.promote", { name: prompt ? undefined : undefined }));
  $("demote").addEventListener("click", () => emit("house.demote", {}));
  $("kick").addEventListener("click", () => emit("house.kick", {}));
})();
