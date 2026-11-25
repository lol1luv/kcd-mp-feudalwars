// Main menu: a left rail of sections, a pane on the right. Every button acts
// through the mode (menu.run {action}) — nothing sends the player to the chat.
// from the mode: {lang, title, keys, sections: {main,world,work,house,trade,build,settings},
//                 cards: [{id, section, title, desc, action}]}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: {
      main: "Overview", world: "The world", work: "Work", house: "House", trade: "Trade",
      build: "Building", settings: "Settings",
      mainTitle: "Feudal Wars", mainLead: "A realm of houses, work and coin. What will you do?",
      worldTitle: "The world", worldLead: "Places to go and things to see.",
      workTitle: "Work", workLead: "Strike the veins with the right tool in your hands.",
      houseTitle: "Your house", houseLead: "Swear fealty, raise the banner, go to war.",
      tradeTitle: "The market", tradeLead: "Sell what you dig, buy what you lack.",
      buildTitle: "The architect", buildLead: "Lay out real objects, save them as a blueprint, stamp copies anywhere.",
      setTitle: "Settings", setLang: "Language", auction: "Open the auction", buildBtn: "Open the architect",
      keysHint: "E — ask about work · F2 — this menu · Esc — close",
    },
    ru: {
      main: "Обзор", world: "Мир", work: "Работа", house: "Дом", trade: "Торг",
      build: "Стройка", settings: "Настройки",
      mainTitle: "Феодальные войны", mainLead: "Королевство домов, труда и монеты. Чем займёшься?",
      worldTitle: "Мир", worldLead: "Куда идти и что смотреть.",
      workTitle: "Работа", workLead: "Бей жилы нужным инструментом в руках.",
      houseTitle: "Твой дом", houseLead: "Присягни, подними знамя, иди на войну.",
      tradeTitle: "Торг", tradeLead: "Продай добытое, купи недостающее.",
      buildTitle: "Зодчий", buildLead: "Разложи настоящие объекты, сохрани чертёж, ставь копии где угодно.",
      setTitle: "Настройки", setLang: "Язык", auction: "Открыть торг", buildBtn: "Открыть зодчего",
      keysHint: "E — спросить о работе · F2 — это меню · Esc — закрыть",
    },
  };

  const SEC_TITLES = { main: ["mainTitle", "mainLead"], world: ["worldTitle", "worldLead"], work: ["workTitle", "workLead"], house: ["houseTitle", "houseLead"], trade: ["tradeTitle", "tradeLead"], build: ["buildTitle", "buildLead"], settings: ["setTitle", ""] };
  const SECTIONS = ["main", "world", "work", "house", "trade", "build", "settings"];

  function switchTo(sec) {
    for (const s of SECTIONS) $("sec-" + s).hidden = s !== sec;
    for (const b of document.querySelectorAll(".rail-nav button")) b.classList.toggle("on", b.dataset.sec === sec);
  }

  for (const b of document.querySelectorAll(".rail-nav button")) {
    b.addEventListener("click", () => switchTo(b.dataset.sec));
  }

  function card(c, t) {
    const btn = document.createElement("button");
    btn.className = "card";
    const tt = document.createElement("span"); tt.className = "card-t"; tt.textContent = c.title;
    const dd = document.createElement("span"); dd.className = "card-d"; dd.textContent = c.desc || "";
    btn.append(tt, dd);
    btn.addEventListener("click", () => KcdMp.emitServer("menu.run", { action: c.action }));
    return btn;
  }

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;

    $("rail-title").textContent = data.title || "Feudal Wars";
    for (const s of SECTIONS) {
      $("nav-" + s).textContent = t[s];
      const [tt, ld] = SEC_TITLES[s];
      if (s !== "main") $("pane-title").textContent = t[tt];  // updated per section below
    }
    $("close").textContent = "×";
    $("cursor").textContent = data.lang === "ru" ? "Мышь" : "Mouse";
    $("trade-h").textContent = t.tradeTitle;
    $("trade-lead").textContent = t.tradeLead;
    $("open-auction").textContent = t.auction;
    $("build-h").textContent = t.buildTitle;
    $("build-lead").textContent = t.buildLead;
    $("open-build").textContent = t.buildBtn;
    $("set-h").textContent = t.setTitle;
    $("set-lang").textContent = t.setLang;
    $("keys-hint").textContent = t.keysHint;

    // per-section headings update when a section opens
    const headUpdate = (sec) => {
      const [tt, ld] = SEC_TITLES[sec];
      $("pane-title").textContent = t[tt] || "";
      $("pane-lead").textContent = ld ? (t[ld] || "") : "";
    };
    for (const b of document.querySelectorAll(".rail-nav button")) {
      b.addEventListener("click", () => headUpdate(b.dataset.sec));
    }
    headUpdate("main");

    const buckets = { main: [], world: [], work: [], house: [], trade: [], build: [] };
    for (const c of data.cards || []) {
      (buckets[c.section] || buckets.main).push(c);
    }
    $("hero-cards").replaceChildren(...buckets.main.map((c) => card(c, t)));
    $("world-cards").replaceChildren(...buckets.world.map((c) => card(c, t)));
    $("work-cards").replaceChildren(...buckets.work.map((c) => card(c, t)));
    $("house-cards").replaceChildren(...buckets.house.map((c) => card(c, t)));

    switchTo("main");
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("menu.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("menu.close"); });
  $("cursor").addEventListener("click", () => KcdMp.emitServer("menu.cursor"));
  $("open-auction").addEventListener("click", () => KcdMp.emitServer("menu.run", { action: "auction" }));
  $("open-build").addEventListener("click", () => KcdMp.emitServer("menu.run", { action: "build" }));
  $("lang-en").addEventListener("click", () => KcdMp.emitServer("menu.lang", { lang: "en" }));
  $("lang-ru").addEventListener("click", () => KcdMp.emitServer("menu.lang", { lang: "ru" }));
  KcdMp.emitServer("menu.ready");
})();