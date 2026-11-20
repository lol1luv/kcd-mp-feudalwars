// A world map window: the game's own map of the server's level, the towns' detailed maps, and a marker for every player.
//
//   from the mode   KcdMp.onMessage({players: [{id, name, x, y, you}]}) - world positions, once a second while the window is open
//   to the mode     KcdMp.emitServer("map.close") - the Close button; KcdMp.emitServer("map.click", {x, y}) - a click on the map
// KcdMp.mapImage is the address of the map's picture (every player's game makes it from its own files); KcdMp.mapInfo says how big
// it is and where its towns are, KcdMp.worldToMap / mapToWorld turn world positions into places on it and back. Player names are
// the players' own: they go on the page with textContent. Opened in a browser (with sdk.js next to the folder) the page runs in
// mock mode with a stand-in picture and a few made-up players.
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  let info = null;      // KcdMp.mapInfo's answer
  let town = null;      // the town whose map is open, null = the region's
  let players = [];

  // the picture now shown: its full size, in the pixels worldToMap answers in
  const size = () => (town ? { w: town.pictureWidth, h: town.pictureHeight } : { w: info.width, h: info.height });

  function place(el, x, y, w, h) {
    const s = size();
    el.style.left = (x / s.w * 100) + "%";
    el.style.top = (y / s.h * 100) + "%";
    if (w !== undefined) {
      el.style.width = (w / s.w * 100) + "%";
      el.style.height = (h / s.h * 100) + "%";
    }
  }

  function drawMarkers() {
    if (!info) return;
    const s = size();
    $("markers").replaceChildren(...players.flatMap((p) => {
      const at = KcdMp.worldToMap(info, p.x, p.y, town ? town.name : undefined);
      if (!at || at.x < 0 || at.y < 0 || at.x > s.w || at.y > s.h) return [];   // off this picture (out of the town)
      const dot = document.createElement("div");
      dot.className = p.you ? "marker you" : "marker";
      const label = document.createElement("span");
      label.textContent = p.name;
      dot.append(label);
      place(dot, at.x, at.y);
      return [dot];
    }));
  }

  function show(next) {
    town = next;
    $("map").src = KcdMp.mapImage({ town: town ? town.name : undefined, width: 2048 });
    $("title").textContent = town ? "Map of " + town.name.replace(/_/g, " ") : "World map";
    $("back").hidden = !town || !info.picture;
    // the towns' outlines on the region's map: a click opens the town's own
    $("towns").replaceChildren(...(town ? [] : info.towns.map((t) => {
      const box = document.createElement("div");
      box.className = "town";
      box.title = t.name.replace(/_/g, " ");
      place(box, t.x, t.y, t.width, t.height);
      box.addEventListener("click", () => show(t));
      return box;
    })));
    drawMarkers();
  }

  // a click on the picture: the world position there, for the mode
  $("map").addEventListener("click", (event) => {
    if (!info) return;
    const box = $("map").getBoundingClientRect(), s = size();
    const x = (event.clientX - box.left) / box.width * s.w;
    const y = (event.clientY - box.top) / box.height * s.h;
    const world = KcdMp.mapToWorld(info, x, y, town ? town.name : undefined);
    if (!world) return;
    $("where").textContent = "Clicked " + Math.round(world.x) + ", " + Math.round(world.y);
    KcdMp.emitServer("map.click", { x: world.x, y: world.y }).catch(() => {});
  });

  KcdMp.onMessage((data) => {
    if (!data || !Array.isArray(data.players)) return;
    players = data.players;
    drawMarkers();
  });

  $("back").addEventListener("click", () => show(null));
  $("close").addEventListener("click", () => KcdMp.emitServer("map.close").catch(() => {}));

  KcdMp.mapInfo().then((answer) => {
    info = answer;
    if (!info || (!info.picture && info.towns.length === 0)) {
      $("sheet").hidden = true;
      $("nomap").hidden = false;
      return;
    }
    show(info.picture ? null : info.towns[0]);   // Sedletz has no region map: its first town's
  }).catch((e) => KcdMp.log.warn("no map: " + e.message));

  // ---- in a browser: a few made-up players around Kuttenberg
  if (KcdMp.env.mock) {
    KcdMp.mock.message({
      players: [
        { id: 1, name: "Henry", x: 3107, y: 747, you: true },
        { id: 2, name: "Hans", x: 752, y: 3346, you: false },
        { id: 3, name: "Mutt", x: 1889, y: 2992, you: false },
      ],
    });
  }
})();
