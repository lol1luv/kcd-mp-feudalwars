// House hall. from the mode: KcdMp.onMessage({lang, name, house, treasury, prestige, money, members, wars})
//   to the mode: house.close, house.donate {amount}, house.prestige, house.declare {enemy}, house.peace
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { house: "House", roster: "Roster", treasury: "Treasury", wars: "Wars", rosterLead: "Retainers of the house. The lord leads; the steward keeps the purse.", treasuryLead: "The house's purse. Taxes flow in; the upkeep of every retainer flows out.", warsLead: "Declarations of war cost the treasury 5 000 groschen. Wins take the spoils.", name: "Name", rank: "Rank", status: "Status", online: "in the realm", away: "away", treasuryRow: "Treasury", prestigeRow: "Prestige", purseRow: "Your purse", enemy: "Enemy", score: "Score", since: "Since", donate: "Donate 100 groschen", prestigeBtn: "Raise prestige (10 000)", declare: "Declare war", peace: "Sue for peace", enemyPh: "house name", groschen: "groschen" },
    ru: { house: "Дом", roster: "Люди", treasury: "Казна", wars: "Войны", rosterLead: "Люди дома. Лорд правит, стольник держит казну.", treasuryLead: "Казна дома. Налоги текут внутрь, содержание людей — наружу.", warsLead: "Объявление войны стоит казне 5 000 грошей. Победа забирает трофеи.", name: "Имя", rank: "Звание", status: "Где", online: "в игре", away: "нет", treasuryRow: "Казна", prestigeRow: "Престиж", purseRow: "Твой кошель", enemy: "Враг", score: "Счёт", since: "Когда", donate: "Пожертвовать 100 грошей", prestigeBtn: "Поднять престиж (10 000)", declare: "Объявить войну", peace: "Заключить мир", enemyPh: "имя дома", groschen: "грошей" },
  };

  function show(tab) {
    for (const b of document.querySelectorAll("#tabs button")) b.setAttribute("aria-selected", String(b.dataset.tab === tab));
    for (const p of document.querySelectorAll("[data-panel]")) p.hidden = p.dataset.panel !== tab;
  }
  for (const b of document.querySelectorAll("#tabs button")) b.addEventListener("click", () => show(b.dataset.tab));

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.house + " " + (data.house || "?");
    $("tab-roster").textContent = t.roster;
    $("tab-treasury").textContent = t.treasury;
    $("tab-wars").textContent = t.wars;
    $("roster-lead").textContent = t.rosterLead;
    $("treasury-lead").textContent = t.treasuryLead;
    $("wars-lead").textContent = t.warsLead;
    $("th-name").textContent = t.name;
    $("th-rank").textContent = t.rank;
    $("th-status").textContent = t.status;
    $("th-enemy").textContent = t.enemy;
    $("th-score").textContent = t.score;
    $("th-since").textContent = t.since;
    $("donate").textContent = t.donate;
    $("prestige").textContent = t.prestigeBtn;
    $("declare").textContent = t.declare;
    $("peace").textContent = t.peace;
    $("enemyName").placeholder = t.enemyPh;

    const tbody = document.querySelector("#members tbody");
    tbody.replaceChildren();
    for (const m of data.members || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = m.name;
      const td2 = document.createElement("td");
      const badge = document.createElement("span"); badge.className = "badge"; badge.textContent = m.rank;
      td2.append(badge);
      const td3 = document.createElement("td"); td3.textContent = m.online ? t.online : t.away;
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
    row(t.treasuryRow, Number(data.treasury || 0).toLocaleString() + " " + t.groschen);
    row(t.prestigeRow, String(Number(data.prestige || 1)));
    row(t.purseRow, Number(data.money || 0).toLocaleString() + " " + t.groschen);

    const wbody = document.querySelector("#warlist tbody");
    wbody.replaceChildren();
    for (const w of data.wars || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = w.enemy;
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
})();
