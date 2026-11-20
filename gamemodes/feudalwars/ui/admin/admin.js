// The admin console.  from the mode: KcdMp.onMessage({players: [{id, name, house, money, ping}], log: [text...]})
//   to the mode: admin.close, admin.kick {id, reason}, admin.ban {id, minutes, reason}, admin.tp {id},
//                admin.heal {id}, admin.money {id, amount}, admin.slap {id}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");

    const tbody = document.querySelector("#players tbody");
    tbody.replaceChildren();
    for (const p of data.players || []) {
      const tr = document.createElement("tr");

      const td = (text) => { const t = document.createElement("td"); t.textContent = text; return t; };
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
        btn("Heal", "admin.heal"),
        btn("Slap", "admin.slap"),
        btn("+100", "admin.money", { amount: 100 }),
        btn("-100", "admin.money", { amount: -100 }),
        btn("Tp", "admin.tp"),
        btn("Kick", "admin.kick", { reason: "the crown wills it" }),
        btn("Ban 1h", "admin.ban", { minutes: 60, reason: "the crown wills it" })
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
})();
