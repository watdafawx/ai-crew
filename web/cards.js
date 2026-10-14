// AI Crew's crew cards (cards.html). The mod (cards.lua) sends {cards: [...]} whenever something on them changed:
// per crew member name, color [r, g, b], trait, mode, doing, state ("idle" "work" "fight" "retreat" "down"), talk (the
// line they're saying, or none), hp, max, slots [{item, n, icon ("<mod>/<path>|<size>"), tip}] (armor, gun, ammo,
// fish), range, kills, built, trips, deaths, back (seconds until a fallen one is back). A click on a card sends
// {cmd: "open", name}: the mod opens their inventory.
(() => {
  "use strict";
  const root = document.getElementById("cards");
  const MODE = { roam: "Roaming", follow: "Following", stay: "Staying" };
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const icon = (id) => `<svg><use href="#i-${id}"/></svg>`;
  const hpColor = (f) => f > 0.6 ? "#5fd35f" : f > 0.3 ? "#f2c14b" : "#ff4a3d";
  const cards = new Map();  // name -> its card's parts

  function make(name) {
    const c = el("div", "card");
    c.dataset.fseSolid = "";
    c.dataset.name = name;
    const head = el("div", "head");
    const mode = el("span", "mode");
    head.append(el("span", "name", name), mode);
    const trait = el("div", "trait");
    const doing = el("div", "doing");
    const text = el("span");
    doing.append(el("i", "dot"), text);
    const hp = el("div", "hp"), bar = el("div", "bar"), fill = el("i"), hpText = el("span");
    bar.append(fill);
    hp.append(bar, hpText);
    const gear = el("div", "gear"), grid = el("div", "slots");
    const slots = [0, 1, 2, 3].map(() => {
      const s = el("div", "slot");
      s.append(el("b"));
      grid.append(s);
      return s;
    });
    const range = el("div", "range");
    gear.append(grid, range);
    const rec = el("div", "rec");
    c.append(head, trait, doing, hp, gear, rec);
    c.addEventListener("mouseenter", () => c.classList.add("up"));
    c.addEventListener("mouseleave", () => c.classList.remove("up"));
    c.addEventListener("click", () => { if (!c.classList.contains("down")) fse.send({ cmd: "open", name }); });
    const parts = { c, trait, mode, text, fill, hpText, slots, range, rec };
    cards.set(name, parts);
    return parts;
  }

  function fill(p, d) {
    const [r, g, b] = (d.color || [1, 0.55, 0.2]).map((x) => Math.round(x * 255));
    p.c.style.setProperty("--c", `rgb(${r} ${g} ${b})`);
    p.c.style.setProperty("--c-rgb", `${r} ${g} ${b}`);
    const talk = d.talk && d.state !== "down";
    // (rest: idle and quiet, or down: sunk to a strip, up when hovered)
    const rest = !talk && (d.state === "idle" || d.state === "down" || !d.state);
    let cls = "card " + (d.state || "idle") + (talk ? " talk" : "") + (rest ? " rest" : "");
    if (p.c.classList.contains("up")) cls += " up";  // (kept up while the mouse is on it)
    if (p.c.className !== cls) p.c.className = cls;
    const down = d.state === "down";
    p.trait.textContent = d.trait || "";
    p.mode.textContent = down ? "" : MODE[d.mode] || "";
    const line = down ? `Down, back in ${d.back} s` : d.talk ? `“${d.talk}”` : d.doing || "";
    p.text.textContent = line;
    p.c.title = down ? line : `${d.name}: ${d.doing}\nClick: their pockets`;
    const f = d.max > 0 ? Math.max(0, Math.min(1, d.hp / d.max)) : 0;
    p.fill.style.width = `${f * 100}%`;
    p.fill.style.backgroundColor = hpColor(f);
    p.hpText.textContent = down ? "" : `${Math.round(d.hp)}/${Math.round(d.max)}`;
    (d.slots || []).forEach((s, i) => {
      const e = p.slots[i];
      if (!e) return;
      const path = s.icon ? s.icon.split("|")[0] : "";
      const want = path ? `url("/mod/${path}")` : "";
      if (e.dataset.icon !== want) { e.style.backgroundImage = want; e.dataset.icon = want; }
      e.classList.toggle("none", !s.item);
      e.firstChild.textContent = s.item && s.n > 1 ? String(s.n) : "";
      e.title = s.tip || "";
    });
    p.range.innerHTML = down ? "" : d.range ? `<b>${d.range}</b>range` : "unarmed";
    p.rec.innerHTML = `<span title="Kills">${icon("kill")}${d.kills}</span>`
      + `<span title="Built">${icon("built")}${d.built}</span>`
      + `<span title="Trips (car, train, jetpack)">${icon("trip")}${d.trips}</span>`
      + `<span title="Times down">${icon("down")}${d.deaths}</span>`;
  }

  function render(list) {
    const seen = new Set();
    list.forEach((d, i) => {
      seen.add(d.name);
      const p = cards.get(d.name) || make(d.name);
      fill(p, d);
      if (root.children[i] !== p.c) root.insertBefore(p.c, root.children[i] || null);
    });
    for (const [name, p] of cards) if (!seen.has(name)) { p.c.remove(); cards.delete(name); }
  }

  fse.on((m) => { if (m && m.cards) render(m.cards); });
  fse.send({ cmd: "ready" });
  // (opened in a plain browser: a sample, to look at the design)
  if (fse.standalone) {
    const slot = (item, n, path) => ({ item, n, icon: path && `base/graphics/icons/${path}.png|64`, tip: item || "None" });
    const none = () => [slot(), slot(), slot(), slot()];
    render([
      { name: "Bolt", color: [1, 0.9, 0.3], trait: "eager", mode: "roam", doing: "building +2", state: "work", hp: 250,
        max: 250, slots: none(), range: 0, kills: 0, built: 132, trips: 4, deaths: 0 },
      { name: "Juno", color: [0.6, 1, 0.4], trait: "precise", state: "down", back: 42, hp: 0, max: 250, slots: none(),
        kills: 1, built: 20, trips: 0, deaths: 1 },
      { name: "Mara", color: [0.3, 0.8, 1], trait: "upbeat", mode: "stay", doing: "waiting here", talk: "Sure thing!",
        state: "idle", hp: 250, max: 250, slots: [slot(), slot("pistol", 1, "pistol"),
          slot("firearm-magazine", 10, "firearm-magazine"), slot()], range: 15, kills: 2, built: 3, trips: 1, deaths: 0 },
      { name: "Rook", color: [1, 0.55, 0.2], trait: "gruff", mode: "follow", doing: "fighting medium biter",
        state: "fight", hp: 150, max: 250, slots: [slot("heavy-armor", 1, "heavy-armor"),
          slot("submachine-gun", 1, "submachine-gun"), slot("firearm-magazine", 40, "firearm-magazine"),
          slot("raw-fish", 12, "fish")], range: 18, kills: 7, built: 40, trips: 2, deaths: 1 },
    ]);
  }
})();
