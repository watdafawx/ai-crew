// AI Crew's crew cards (cards.html). The mod (cards.lua) sends {cards: [...]} whenever something on them changed:
// per crew member name, color [r, g, b], trait, mode, doing, state ("idle" "work" "fight" "retreat" "down"), talk (the
// line they're saying, or none), hp, max, slots [{item, n, icon ("<mod>/<path>|<size>"), tip}] (armor, gun, ammo,
// fish), range, kills, built, trips, deaths, back (seconds until a fallen one is back). A click on a card sends
// {cmd: "open", name}: the mod opens their pockets. The corner card's buttons send {cmd: "order", act}: an order for
// everyone (build, deconstruct, upgrade, deliver, follow, roam, stop, attack: Clear nests).
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
  const hpColor = (f) => f > 0.6 ? "#5fd35f" : f > 0.3 ? "#f2c14b" : "#ff4a3d";
  const cards = new Map();  // name -> its card's parts

  function make(name) {
    const c = el("div", "card");
    c.dataset.fseSolid = "";
    c.dataset.name = name;
    const head = el("div", "head");
    const trait = el("span", "trait"), mode = el("span", "mode");
    head.append(el("span", "name", name), trait, mode);
    const bar = el("div", "bar"), fill = el("i"), hpText = el("span");
    bar.append(fill, hpText);
    const line = el("div", "line"), doing = el("div", "doing"), text = el("span"), grid = el("div", "slots");
    doing.append(el("i", "dot"), text);
    const slots = [0, 1, 2, 3].map(() => {
      const s = el("div", "slot");
      s.append(el("b"));
      grid.append(s);
      return s;
    });
    line.append(doing, grid);
    c.append(head, bar, line);
    c.addEventListener("click", () => { if (!c.classList.contains("down")) fse.send({ cmd: "open", name }); });
    const parts = { c, trait, mode, text, fill, hpText, slots };
    cards.set(name, parts);
    return parts;
  }

  function fill(p, d) {
    const [r, g, b] = (d.color || [1, 0.55, 0.2]).map((x) => Math.round(x * 255));
    p.c.style.setProperty("--c", `rgb(${r} ${g} ${b})`);
    p.c.style.setProperty("--c-rgb", `${r} ${g} ${b}`);
    const down = d.state === "down";
    const talk = d.talk && !down;
    const cls = "card " + (d.state || "idle") + (talk ? " talk" : "");
    if (p.c.className !== cls) p.c.className = cls;
    p.trait.textContent = d.trait || "";
    p.mode.textContent = down ? `back in ${d.back} s` : MODE[d.mode] || "";
    p.text.textContent = down ? "Down" : talk ? `\u201c${d.talk}\u201d` : d.doing || "";
    p.c.title = (down ? `${d.name}: down, back in ${d.back} s` : `${d.name}: ${d.doing}`)
      + `\nKills ${d.kills} \u00b7 Built ${d.built} \u00b7 Trips ${d.trips} \u00b7 Down ${d.deaths}`
      + (down ? "" : "\nClick: their pockets");
    const f = d.max > 0 ? Math.max(0, Math.min(1, d.hp / d.max)) : 0;
    p.fill.style.width = `${f * 100}%`;
    p.fill.style.backgroundColor = hpColor(f);
    p.hpText.textContent = down ? "" : `${Math.round(d.hp)} / ${Math.round(d.max)}`;
    (d.slots || []).forEach((s, i) => {
      const e = p.slots[i];
      if (!e) return;
      const path = s.icon ? s.icon.split("|")[0] : "";
      const want = path ? `url("/mod/${path}")` : "";
      if (e.dataset.icon !== want) { e.style.backgroundImage = want; e.dataset.icon = want; }
      e.classList.toggle("none", !s.item);
      e.firstChild.textContent = s.item && s.n > 1 ? String(s.n) : "";
      e.title = (s.tip || "") + (i === 1 && s.item && d.range ? ` (range ${d.range})` : "");
    });
  }

  // the orders for everyone (the window's dock): a card of its own at the top; a click sends {cmd: "order", act}
  const ORDERS = [
    ["build", "Build", "Place the ghosts near you now (making what's missing)"],
    ["deconstruct", "Deconstruct", "Remove what's marked for deconstruction near you"],
    ["upgrade", "Upgrade", "Carry out the upgrade planner's marks near you"],
    ["deliver", "Deliver", "Bring you everything they carry"],
    ["follow", "Follow me", "All of them follow you"],
    ["roam", "Roam", "Wander round you on their own, dealing with what they find"],
    ["stop", "Stop all", "All of them drop all their jobs"],
    ["attack", "Clear nests", "Destroy the enemy spawners and worms within 96 tiles of you"],
  ];
  let cmdCard = null;
  function commands() {
    if (cmdCard) return cmdCard;
    cmdCard = el("div", "card cmds");
    cmdCard.dataset.fseSolid = "";
    cmdCard.append(el("div", "cmds-title", "Everyone"));
    const grid = el("div", "cmd-grid");
    for (const [act, name, tip] of ORDERS) {
      const b = el("button", "cmd");
      b.dataset.act = act;
      b.title = `${name}: ${tip}`;
      b.innerHTML = `<svg><use href="#o-${act}"/></svg>`;
      b.addEventListener("click", (e) => {
        e.stopPropagation();
        fse.send({ cmd: "order", act });
        b.classList.remove("sent");
        void b.offsetWidth;  // (the flash again on a second click)
        b.classList.add("sent");
      });
      grid.append(b);
    }
    cmdCard.append(grid);
    return cmdCard;
  }

  function render(list) {
    const seen = new Set();
    const lead = list.length > 0 ? 1 : 0;  // (the orders' card first: on top)
    if (lead) { if (root.children[0] !== commands()) root.insertBefore(commands(), root.children[0] || null); }
    else if (cmdCard) { cmdCard.remove(); }
    list.forEach((d, i) => {
      seen.add(d.name);
      const p = cards.get(d.name) || make(d.name);
      fill(p, d);
      if (root.children[i + lead] !== p.c) root.insertBefore(p.c, root.children[i + lead] || null);
    });
    for (const [name, p] of cards) if (!seen.has(name)) { p.c.remove(); cards.delete(name); }
  }

  fse.on((m) => {
    if (!m || !m.cards) return;
    root.classList.toggle("left", m.side !== "bottom-right");  // (centre left, else bottom right)
    render(m.cards);
  });
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
