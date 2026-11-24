// Admin console. from the mode: KcdMp.onMessage({lang, players, log})
//   to the mode: admin.close, admin.kick {id, reason}, admin.ban {id, minutes, reason}, admin.tp {id},
//                admin.heal {id}, admin.money {id, amount}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Crown's console", lead: "Souls in the realm. Actions land at once; the log below keeps the tale.", name: "Name", house: "House", purse: "Purse", act: "Actions", heal: "Heal", plus: "+100", minus: "-100", tp: "Tp", kick: "Kick", ban1h: "Ban 1h" },
    ru: { title: "Совет короны", lead: "Души королевства. Действия применяются сразу, летопись — ниже.", name: "Имя", house: "Дом", purse: "Кошелёк", act: "Действия", heal: "Лечить", plus: "+100", minus: "-100", tp: "К себе", kick: "Кик", ban1h: "Бан 1ч" },
  };

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("th-name").textContent = t.name;
    $("th-house").textContent = t.house;
    $("th-purse").textContent = t.purse;
    $("th-act").textContent = t.act;

    const tbody = document.querySelector("#players tbody");
    tbody.replaceChildren();
    for (const p of data.players || []) {
      const tr = document.createElement("tr");
      const td = (text) => { const e = document.createElement("td"); e.textContent = text; return e; };
      tr.append(td(p.id), td(p.name), td(p.house || "-"), td(Number(p.money || 0).toLocaleString()), td(p.ping + " ms"));
      const acts = document.createElement("td");
      const btn = (label, ev, payload) => {
        const b = document.createElement("button");
        b.className = "act";
        b.textContent = label;
        b.addEventListener("click", () => KcdMp.emitServer(ev, Object.assign({ id: p.id }, payload || {})));
        return b;
      };
      acts.append(
        btn(t.heal, "admin.heal"),
        btn(t.plus, "admin.money", { amount: 100 }),
        btn(t.minus, "admin.money", { amount: -100 }),
        btn(t.tp, "admin.tp"),
        btn(t.kick, "admin.kick", { reason: "the crown wills it" }),
        btn(t.ban1h, "admin.ban", { minutes: 60, reason: "banned by the crown" })
      );
      tr.append(acts);
      tbody.append(tr);
    }

    const log = $("log");
    log.replaceChildren(...(data.log || []).map((line) => {
      const div = document.createElement("div");
      div.textContent = line;
      return div;
    }));
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("admin.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("admin.close"); });
})();
