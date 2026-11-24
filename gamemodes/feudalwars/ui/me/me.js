// Character page. from the mode: KcdMp.onMessage({lang, name, money, house, treasury, prestige, war, rank, admin, level})
//   to the mode: me.close, menu.run {cmd}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Character", law: "The realm's law: wars are declared from the house hall, taxes keep the treasury, and the upkeep of every retainer is paid each minute.", hall: "House hall", menu: "Menu", name: "Name", purse: "Purse", house: "House", nohouse: "none — /house create or /house join", rank: "Rank", treasury: "Treasury", prestige: "Prestige", war: "At war with", peace: "nobody — the realm is at peace", land: "Land", standing: "Standing", admin: "an admin of the realm", common: "a commoner", groschen: "groschen" },
    ru: { title: "Персонаж", law: "Закон королевства: войны объявляются из зала дома, налоги наполняют казну, за каждого человека каждый час платится содержание.", hall: "Зал дома", menu: "Меню", name: "Имя", purse: "Кошелёк", house: "Дом", nohouse: "нет — /house create или /house join", rank: "Звание", treasury: "Казна", prestige: "Престиж", war: "Война с", peace: "никем — в королевстве мир", land: "Земля", standing: "Положение", admin: "слуга короны", common: "простолюдин", groschen: "грошей" },
  };

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("law").textContent = t.law;
    $("go-hall").textContent = t.hall;
    $("go-menu").textContent = t.menu;
    $("seal-name").textContent = data.name || "";
    const list = $("you");
    list.replaceChildren();
    const row = (term, value) => {
      const dt = document.createElement("dt"); dt.textContent = term;
      const dd = document.createElement("dd"); dd.textContent = value;
      list.append(dt, dd);
    };
    row(t.name, data.name || "");
    row(t.purse, Number(data.money || 0).toLocaleString() + " " + t.groschen);
    row(t.house, data.house ? data.house : t.nohouse);
    if (data.house) {
      row(t.rank, data.rank || "");
      row(t.treasury, Number(data.treasury || 0).toLocaleString() + " " + t.groschen);
      row(t.prestige, String(Number(data.prestige || 1)));
      row(t.war, data.war ? data.war : t.peace);
    }
    row(t.land, data.level || "");
    row(t.standing, data.admin ? t.admin : t.common);
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("me.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("me.close"); });
  $("go-hall").addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: "/hall" }));
  $("go-menu").addEventListener("click", () => KcdMp.emitServer("menu.run", { cmd: "/menu" }));
})();
