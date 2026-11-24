// Workshop. from the mode: {lang, recipes:[{id,out,amount,need,station,station_label,have_skill}]}
//   to the mode: craft.close, craft.make {id}
(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const L = {
    en: { title: "Workshop", lead: "Bring the goods to the right station and turn raw into finished: ore to ingot, timber to plank, grain to bread.", out: "Makes", need: "Needs", station: "At", make: "Make", skill: "skill" },
    ru: { title: "Мастерская", lead: "Принеси товар к нужному верстаку и преврати сырьё в изделие: руда — слиток, бревно — доска, зерно — хлеб.", out: "Изделие", need: "Нужно", station: "Где", make: "Сделать", skill: "навык" },
  };

  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    const t = L[data.lang] || L.en;
    $("title").textContent = t.title;
    $("lead").textContent = t.lead;
    $("th-out").textContent = t.out;
    $("th-need").textContent = t.need;
    $("th-station").textContent = t.station;

    const tbody = document.querySelector("#recipes tbody");
    tbody.replaceChildren();
    for (const r of data.recipes || []) {
      const tr = document.createElement("tr");
      const td = (text) => { const e = document.createElement("td"); e.textContent = text; return e; };
      tr.append(td(r.out + " ×" + r.amount), td(r.need), td(r.station_label + " · " + t.skill + " " + r.have_skill));
      const acts = document.createElement("td");
      const b = document.createElement("button");
      b.className = "act gold"; b.textContent = t.make;
      b.addEventListener("click", () => KcdMp.emitServer("craft.make", { id: r.id }));
      acts.append(b);
      tr.append(acts);
      tbody.append(tr);
    }
  });

  $("close").addEventListener("click", () => KcdMp.emitServer("craft.close"));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") KcdMp.emitServer("craft.close"); });
})();