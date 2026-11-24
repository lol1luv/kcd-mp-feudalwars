// Architect. from the mode: KcdMp.onMessage({lang, structures:[{key,label}], blueprints:[{key,label,parts}], has_draft, draft_parts})
//   to the mode: build.close, build.new {name}, build.save {name}, build.stamp {name}, build.cancel
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Architect", lead: "Lay out real objects beside you, break a rock to see it work, then save what stands as a blueprint and stamp copies anywhere.",
      draft: "Start a draft", bps: "Your blueprints", noBps: "No blueprints yet — lay one out and save it.",
      bpName: "Blueprint", bpParts: "Parts", stamp: "Stamp here", del: "Forget",
      draftHint: "A draft stands before you. Strike its rocks: they break and drop ore. Save it to keep it.",
      save: "Save draft as", cancel: "Sweep the draft", parts: "parts", draftNow: "draft laid", noDraft: "no draft" },
    ru: { title: "Зодчий", lead: "Разложи настоящие объекты рядом с собой, разбей камень — увидишь, как это работает, — затем сохрани то, что стоит, как чертёж и ставь копии где угодно.",
      draft: "Начать черновик", bps: "Твои чертежи", noBps: "Чертежей пока нет — разложи и сохрани.",
      bpName: "Чертёж", bpParts: "Частей", stamp: "Поставить здесь", del: "Забыть",
      draftHint: "Черновик стоит перед тобой. Бей его камни: они ломаются и дают руду. Сохрани, чтобы оставить.",
      save: "Сохранить черновик как", cancel: "Смести черновик", parts: "частей", draftNow: "черновик разложен", noDraft: "черновика нет" },
  };

  let state = null;

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    state = data;
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("draft-h").textContent = t.draft;
    $("bp-h").textContent = t.bps;
    $("th-bp-name").textContent = t.bpName;
    $("th-bp-parts").textContent = t.bpParts;
    $("foot").textContent = data.has_draft ? (t.draftNow + " (" + data.draft_parts + " " + t.parts + ")") : t.noDraft;

    const row = $("draft-row");
    row.replaceChildren();
    for (const s of data.structures || []) {
      const b = document.createElement("button");
      b.className = "card"; b.type = "button";
      const tt = document.createElement("span"); tt.className = "card-t"; tt.textContent = s.label;
      b.append(tt);
      b.addEventListener("click", () => KcdMp.emitServer("build.new", { name: s.key }));
      row.append(b);
    }

    const bpRow = document.querySelector("#bps tbody");
    bpRow.replaceChildren();
    const list = data.blueprints || [];
    if (list.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td"); td.colSpan = 3; td.textContent = t.noBps;
      td.style.fontStyle = "italic";
      tr.append(td); bpRow.append(tr);
    }
    for (const bp of list) {
      const tr = document.createElement("tr");
      const tdName = document.createElement("td"); tdName.textContent = bp.label;
      const tdParts = document.createElement("td"); tdParts.textContent = String(bp.parts);
      const tdAct = document.createElement("td");
      const stamp = document.createElement("button");
      stamp.className = "act gold"; stamp.textContent = t.stamp;
      stamp.addEventListener("click", () => KcdMp.emitServer("build.stamp", { name: bp.key }));
      tdAct.append(stamp);
      tr.append(tdName, tdParts, tdAct);
      bpRow.append(tr);
    }

    if (data.has_draft) {
      const saveWrap = document.createElement("div");
      saveWrap.style.marginTop = "10px";
      const nameIn = document.createElement("input");
      nameIn.type = "text"; nameIn.placeholder = t.save; nameIn.style.width = "200px";
      const saveBtn = document.createElement("button");
      saveBtn.className = "act gold"; saveBtn.textContent = t.save;
      saveBtn.addEventListener("click", () => KcdMp.emitServer("build.save", { name: nameIn.value.trim() }));
      const cancelBtn = document.createElement("button");
      cancelBtn.className = "act"; cancelBtn.textContent = t.cancel;
      cancelBtn.style.marginLeft = "8px";
      cancelBtn.addEventListener("click", () => KcdMp.emitServer("build.cancel"));
      saveWrap.append(nameIn, saveBtn, cancelBtn);
      row.after(saveWrap);
    }
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("build.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("build.close"); });
})();