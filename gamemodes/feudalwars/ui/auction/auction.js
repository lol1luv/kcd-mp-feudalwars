// Auction. from the mode: KcdMp.onMessage({lang, lots: [{id, res_name, amount, price, seller, mine}], bag: [{res, name, have}], money})
//   to the mode: auction.close, auction.sell {res, amount, price}, auction.buy {id}, auction.cancel {id}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Auction", lead: "The market square. Coin for goods, goods for coin — no shouting needed.", lots: "Lots", res: "Goods", amount: "Amount", price: "Price", seller: "Seller", buy: "Buy", cancel: "Take back", sell: "Put up for sale", bagRes: "Your goods", have: "Hold", bagAmount: "Amount", bagPrice: "Price", sellBtn: "Sell", purse: "Purse", groschen: "groschen" },
    ru: { title: "Торг", lead: "Торговая площадь. Монета за товар, товар за монету — кричать не нужно.", lots: "Лоты", res: "Товар", amount: "Кол-во", price: "Цена", seller: "Продавец", buy: "Купить", cancel: "Снять", sell: "Выставить на торг", bagRes: "Твои товары", have: "Есть", bagAmount: "Кол-во", bagPrice: "Цена", sellBtn: "Продать", purse: "Кошелёк", groschen: "грошей" },
  };

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("lots-h").textContent = t.lots;
    $("sell-h").textContent = t.sell;
    $("th-res").textContent = t.res;
    $("th-amount").textContent = t.amount;
    $("th-price").textContent = t.price;
    $("th-seller").textContent = t.seller;
    $("th-bag-res").textContent = t.bagRes;
    $("th-have").textContent = t.have;
    $("th-bag-amount").textContent = t.bagAmount;
    $("th-bag-price").textContent = t.bagPrice;
    $("purse").textContent = t.purse + ": " + Number(data.money || 0).toLocaleString() + " " + t.groschen;

    const lots = document.querySelector("#lots tbody");
    lots.replaceChildren();
    for (const lot of data.lots || []) {
      const tr = document.createElement("tr");
      const td = (text) => { const e = document.createElement("td"); e.textContent = text; return e; };
      tr.append(td("#" + lot.id), td(lot.res_name + " × " + lot.amount), td(String(lot.amount)), td(Number(lot.price).toLocaleString()), td(lot.seller));
      const acts = document.createElement("td");
      if (lot.mine) {
        const b = document.createElement("button");
        b.className = "act"; b.textContent = t.cancel;
        b.addEventListener("click", () => KcdMp.emitServer("auction.cancel", { id: lot.id }));
        acts.append(b);
      } else {
        const b = document.createElement("button");
        b.className = "act gold"; b.textContent = t.buy;
        b.addEventListener("click", () => KcdMp.emitServer("auction.buy", { id: lot.id }));
        acts.append(b);
      }
      tr.append(acts);
      lots.append(tr);
    }

    const bag = document.querySelector("#bag tbody");
    bag.replaceChildren();
    for (const b of data.bag || []) {
      if (!b.have) continue;
      const tr = document.createElement("tr");
      const td = (text) => { const e = document.createElement("td"); e.textContent = text; return e; };
      tr.append(td(b.name), td(String(b.have)));
      const amt = document.createElement("td");
      const amtIn = document.createElement("input");
      amtIn.type = "text"; amtIn.value = "1"; amtIn.style.width = "60px";
      amt.append(amtIn);
      const prc = document.createElement("td");
      const prcIn = document.createElement("input");
      prcIn.type = "text"; prcIn.value = "10"; prcIn.style.width = "80px";
      prc.append(prcIn);
      const acts = document.createElement("td");
      const btn = document.createElement("button");
      btn.className = "act gold"; btn.textContent = t.sellBtn;
      btn.addEventListener("click", () => KcdMp.emitServer("auction.sell", { res: b.res, amount: Math.max(1, parseInt(amtIn.value) || 1), price: Math.max(1, parseInt(prcIn.value) || 1) }));
      acts.append(btn);
      tr.append(amt, prc, acts);
      bag.append(tr);
    }
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("auction.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("auction.close"); });
})();
