// A short notice in the corner.  from the mode: KcdMp.onMessage({text})
(() => {
  "use strict";
  KcdMp.onMessage((data) => {
    if (!data || typeof data !== "object") return;
    document.body.classList.add("ready");
    document.getElementById("text").textContent = data.text || "";
  });
})();
