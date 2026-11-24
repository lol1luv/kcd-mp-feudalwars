// NPC page. Two modes:
//   single: {mode:"single", npc:{id,name,role,role_label,stock:[{label,price}]}, actions:[{id,label}]}
//   admin:  {npcs:[...], items:[...]}
//   to the mode: npc.close, npc.action {id, npc}, npc.remove {id}, npc.stock {id,item,price}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "People of the realm", lead: "Place a vendor, a trainer or a guard where you stand: /npc add <role> <name>. Pick their stock here.",
      name: "Name", role: "Role", place: "Where", stock: "Goods", remove: "Remove", stockH: "Goods of the vendor",
      stockLead: "Click a good to put it on the counter at a fair price.", empty: "No people placed yet — stand where you want one and use /npc add vendor <name>.",
      offers: "Offers", price: "Price", close: "Close" },
    ru: { title: "Люди королевства", lead: "Поставь торговца, учителя или стражника там, где стоишь: /npc add <роль> <имя>. Товар выбери здесь.",
      name: "Имя", role: "Роль", place: "Где", stock: "Товар", remove: "Убрать", stockH: "Товары торговца",
      stockLead: "Нажми товар, чтобы выставить его на прилавок по честной цене.", empty: "Пока никого нет — встань, где нужен человек, и введи /npc add vendor <имя>.",
      offers: "Предлагает", price: "Цена", close: "Закрыть" },
  };

  let state = null, selected = 0;

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    state = data;
    const t = L[data.lang] || L.en;

    if (data.mode === "single" && data.npc) {
      renderSingle(data, t);
      return;
    }
    renderAdmin(data, t);
  });

  function renderSingle(data, t) {
    const n = data.npc;
    $("title").textContent = n.name;
    $("lead").textContent = n.role_label;
    $("admin-block").hidden = true;
    $("single-block").hidden = false;
    $("single-role").textContent = n.role_label;

    const acts = $("single-actions");
    acts.replaceChildren();
    for (const a of data.actions || []) {
      const b = document.createElement("button");
      b.className = "act gold big"; b.type = "button";
      b.textContent = a.label;
      b.addEventListener("click", () => KcdMp.emitServer("npc.action", { id: a.id, npc: n.id }));
      acts.append(b);
    }

    const stock = $("single-stock");
    stock.replaceChildren();
    if ((n.stock || []).length) {
      $("single-stock-h").hidden = false;
      for (const row of n.stock) {
        const tr = document.createElement("tr");
        const td1 = document.createElement("td"); td1.textContent = row.label;
        const td2 = document.createElement("td"); td2.textContent = Number(row.price).toLocaleString();
        tr.append(td1, td2);
        stock.append(tr);
      }
    } else {
      $("single-stock-h").hidden = true;
    }
  }

  function renderAdmin(data, t) {
    $("single-block").hidden = true;
    $("admin-block").hidden = false;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("th-name").textContent = t.name;
    $("th-role").textContent = t.role;
    $("th-place").textContent = t.place;
    $("th-stock").textContent = t.stock;
    $("stock-h").textContent = t.stockH;
    $("stock-lead").textContent = t.stockLead;

    const tbody = document.querySelector("#npcs tbody");
    tbody.replaceChildren();
    const list = data.npcs || [];
    if (list.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td"); td.colSpan = 6; td.textContent = t.empty; td.style.fontStyle = "italic";
      tr.append(td); tbody.append(tr);
    }
    for (const n of list) {
      const tr = document.createElement("tr");
      const td = (text) => { const e = document.createElement("td"); e.textContent = text; return e; };
      tr.append(td(String(n.id)), td(n.name), td(n.role_label), td(Math.floor(n.x) + ", " + Math.floor(n.y)), td(String(n.stock || 0)));
      const acts = document.createElement("td");
      const rm = document.createElement("button");
      rm.className = "act"; rm.textContent = t.remove;
      rm.addEventListener("click", () => KcdMp.emitServer("npc.remove", { id: n.id }));
      acts.append(rm);
      tr.append(acts);
      tr.addEventListener("click", (e) => {
        if (e.target.tagName === "BUTTON") return;
        selected = n.id;
        renderStock();
      });
      tbody.append(tr);
    }
    renderStock();
  }

  function renderStock() {
    if (!state) return;
    const t = L[state.lang] || L.en;
    const npc = (state.npcs || []).find((n) => n.id === selected);
    const box = $("stock-box");
    if (!npc || npc.role !== "vendor") { box.hidden = true; $("stock-h").hidden = true; return; }
    box.hidden = false; $("stock-h").hidden = false;
    $("stock-h").textContent = t.stockH + " — " + npc.name;
    const row = $("item-buttons");
    row.replaceChildren();
    for (const it of state.items || []) {
      const b = document.createElement("button");
      b.className = "card"; b.type = "button";
      const tt = document.createElement("span"); tt.className = "card-t"; tt.textContent = it.label;
      const dd = document.createElement("span"); dd.className = "card-d"; dd.textContent = it.price + " gr";
      b.append(tt, dd);
      b.addEventListener("click", () => KcdMp.emitServer("npc.stock", { id: npc.id, item: it.item, price: it.price }));
      row.append(b);
    }
  }

  $("close").addEventListener("click", () => KcdMp.emitServer("npc.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("npc.close"); });
})();