// Your character page.  from the mode: KcdMp.onMessage({name, money, house, treasury, prestige, war, rank, admin, level})
//   to the mode: KcdMp.emitServer("me.close")
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const list = $("you");
    list.replaceChildren();

    const row = (term, value) => {
      const dt = document.createElement("dt");
      dt.textContent = term;
      const dd = document.createElement("dd");
      dd.textContent = value;
      list.append(dt, dd);
    };

    row("Name", data.name || "");
    row("Purse", (Number(data.money || 0)).toLocaleString() + " groschen");
    row("House", data.house ? "the house of " + data.house : "none - /house create or /house join");
    if (data.house) {
      row("Rank", data.rank || "retainer");
      row("Treasury", Number(data.treasury || 0).toLocaleString() + " groschen");
      row("Prestige", "level " + Number(data.prestige || 1));
      row("At war with", data.war ? "the house of " + data.war : "nobody - the realm is at peace");
    }
    row("Land", data.level || "");
    row("Standing", data.admin ? "an admin of the realm" : "a commoner");
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("me.close"));
})();
