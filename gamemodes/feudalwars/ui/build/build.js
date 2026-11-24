// Builder (admins). from the mode: KcdMp.onMessage({lang, structures: [{key, label, cost}]})
//   to the mode: build.close, build.place {name}, build.cancel
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Builder", lead: "The crown raises what it wills. Pick a structure — it stands before you as a preview for a minute.", name: "Structure", cost: "Cost", place: "Raise", cancel: "Tear the preview down", groschen: "groschen" },
    ru: { title: "Зодчий", lead: "Корона строит что пожелает. Выбери постройку — она встанет перед тобой предпросмотром на минуту.", name: "Постройка", cost: "Цена", place: "Возвести", cancel: "Снести предпросмотр", groschen: "грошей" },
  };

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("th-name").textContent = t.name;
    $("th-cost").textContent = t.cost;
    $("cancel").textContent = t.cancel;
    const tbody = document.querySelector("#catalog tbody");
    tbody.replaceChildren();
    for (const s of data.structures || []) {
      const tr = document.createElement("tr");
      const td1 = document.createElement("td"); td1.textContent = s.label;
      const td2 = document.createElement("td"); td2.textContent = Number(s.cost).toLocaleString() + " " + t.groschen;
      const td3 = document.createElement("td");
      const b = document.createElement("button");
      b.className = "act gold"; b.textContent = t.place;
      b.addEventListener("click", () => KcdMp.emitServer("build.place", { name: s.key }));
      td3.append(b);
      tr.append(td1, td2, td3);
      tbody.append(tr);
    }
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("build.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("build.close"); });
  $("cancel").addEventListener("click", () => KcdMp.emitServer("build.cancel"));
})();
