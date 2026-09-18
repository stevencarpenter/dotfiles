/* Repo Atlas client.
   Renders the payload build-site.py produced. Holds no knowledge the pipeline
   did not derive: anything missing here is missing because the tree did not
   carry it, never because this file failed to ask. */

(() => {
  "use strict";

  let DATA = null;
  const open = new Set([""]);
  const el = (id) => document.getElementById(id);

  // ── helpers ──────────────────────────────────────────────────────────────

  const esc = (s) =>
    String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  /** Render backticked spans in maintained prose as inline code. */
  const ticks = (s) => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>");

  const parentOf = (p) => (p.includes("/") ? p.slice(0, p.lastIndexOf("/")) : "");
  const nameOf = (p) => (p.includes("/") ? p.slice(p.lastIndexOf("/") + 1) : p || "/");

  const bytes = (n) =>
    n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} kB` : `${(n / 1048576).toFixed(1)} MB`;

  // ── tree ─────────────────────────────────────────────────────────────────

  function renderTree() {
    const cur = location.hash.slice(2) || "";
    const out = [];

    const walk = (path, depth) => {
      const node = DATA.nodes[path];
      if (!node || !node.children) return;
      for (const child of node.children) {
        const c = DATA.nodes[child];
        if (!c) continue;
        const isDir = c.kind === "dir";
        const expanded = open.has(child);
        const cls = ["row", isDir ? "dir" : "file", child === cur ? "on" : ""].join(" ");
        const tw = isDir ? (expanded ? "▾" : "▸") : "·";
        const flag = c.pending ? "○" : c.excluded ? "–" : "";
        out.push(
          `<div class="${cls}" data-path="${esc(child)}" style="padding-left:${8 + depth * 13}px">` +
            `<span class="tw">${tw}</span>` +
            `<span class="nm">${esc(nameOf(child))}</span>` +
            (flag ? `<span class="badge">${flag}</span>` : "") +
          `</div>`
        );
        if (isDir && expanded) walk(child, depth + 1);
      }
    };
    walk("", 0);
    el("tree").innerHTML = out.join("");
  }

  /** Expand every ancestor of a path so the tree reveals it. */
  function reveal(path) {
    let p = parentOf(path);
    while (p) { open.add(p); p = parentOf(p); }
    open.add("");
  }

  // ── detail: shared blocks ────────────────────────────────────────────────

  function crumbs(path) {
    if (!path) return `<div class="crumb">repository root</div>`;
    const parts = path.split("/");
    const links = parts.map((part, i) => {
      const upto = parts.slice(0, i + 1).join("/");
      return i === parts.length - 1
        ? esc(part)
        : `<a href="#/${esc(upto)}">${esc(part)}</a>`;
    });
    return `<div class="crumb"><a href="#/">~/.dotfiles</a> / ${links.join(" / ")}</div>`;
  }

  function tierPills(n) {
    const p = [];
    p.push(`<span class="pill ${n.structure || n.kind === "dir" ? "on" : "off"}">T0 structure</span>`);
    p.push(`<span class="pill ${n.prose ? "on" : "off"}">T1 authored prose</span>`);
    p.push(`<span class="pill ${n.bindings ? "doc" : "off"}">T2 doc binding</span>`);
    if (n.synthesis) p.push(`<span class="pill on">T3 synthesis</span>`);
    else if (n.pending) p.push(`<span class="pill pend">T3 summary pending</span>`);
    else p.push(`<span class="pill off">T3 not needed</span>`);
    return `<div class="tiers">${p.join("")}</div>`;
  }

  function proseBlock(n) {
    if (!n.prose) return "";
    return `<section class="blk"><h2>Authored prose</h2>
      <div class="card prose">${ticks(n.prose)}
      <span class="ln">from the file itself, line ${n.prose_line}</span></div></section>`;
  }

  function bindingBlock(n) {
    if (!n.bindings) return "";
    const items = n.bindings.map((b) =>
      `<div class="quote">${ticks(b.text)}
        <cite>${esc(b.doc)}${b.heading ? ` › ${esc(b.heading)}` : ""}</cite></div>`
    ).join("");
    return `<section class="blk"><h2>From the maintained docs</h2>${items}</section>`;
  }

  function synthesisBlock(n) {
    if (n.synthesis) {
      return `<section class="blk"><h2>Synthesis</h2>
        <div class="card prose">${ticks(n.synthesis.text)}
        <span class="ln">model-written${n.synthesis.commit ? `, from ${esc(n.synthesis.commit)}` : ""}</span></div></section>`;
    }
    if (n.pending) {
      return `<section class="blk"><h2>Synthesis</h2>
        <div class="card"><p class="note">Summary pending: ${esc(n.pending)}.
        Nothing is shown here rather than something possibly stale.
        Run <code>just site-enrich</code> to fill it.</p></div></section>`;
    }
    return "";
  }

  function gatesBlock(n) {
    const gates = n.structure && n.structure.gates;
    if (!gates || !gates.length) return "";
    const rows = gates.map((g) => {
      const hosts = g.unknown
        ? `<span class="hosts none">capability not in the table</span>`
        : g.hosts.length
          ? `<span class="hosts">${esc(g.hosts.join(", "))}</span>`
          : `<span class="hosts none">no host</span>`;
      return `<div class="gate"><span class="ex">${esc(g.expr)}</span>
        <span style="color:var(--grey0);font-size:.78rem">line ${g.line}</span>${hosts}</div>`;
    }).join("");
    return `<section class="blk"><h2>Active on</h2><div class="gates">${rows}</div></section>`;
  }

  function defsBlock(n) {
    const s = n.structure;
    if (!s) return "";
    if (s.parse_error) {
      return `<section class="blk"><h2>Structure</h2>
        <div class="card"><p class="note">Could not parse: ${esc(s.parse_error)}</p></div></section>`;
    }
    if (s.defs && s.defs.length) {
      const rows = s.defs.map((d) => {
        const kw = d.kind === "class" ? "class" : "def";
        const meths = (d.methods || []).map((m) =>
          `<div class="meth"><div class="sig"><span class="kw">def</span> <span class="nm">${esc(m.name)}</span>${esc(m.signature.slice(m.name.length))}</div>
           ${m.doc ? `<div class="doc">${esc(m.doc)}</div>` : ""}</div>`
        ).join("");
        return `<div class="def">
          <div class="sig"><span class="kw">${kw}</span> <span class="nm">${esc(d.name)}</span>${esc(d.signature.slice(d.name.length))}</div>
          ${d.doc ? `<div class="doc">${esc(d.doc)}</div>` : ""}${meths}</div>`;
      }).join("");
      return `<section class="blk"><h2>Definitions</h2><div class="defs">${rows}</div></section>`;
    }
    if (s.functions && s.functions.length) {
      const rows = s.functions.map((f) =>
        `<div class="def"><div class="sig"><span class="nm">${esc(f.name)}</span>() <span style="color:var(--grey0)">line ${f.line}</span></div></div>`
      ).join("");
      return `<section class="blk"><h2>Functions</h2><div class="defs">${rows}</div></section>`;
    }
    if (s.outline && s.outline.length) {
      const rows = s.outline.map((h) =>
        `<div class="def"><div class="sig" style="padding-left:${(h.level - 1) * 16}px">
          <span style="color:var(--grey0)">${"#".repeat(h.level)}</span> ${esc(h.text)}</div></div>`
      ).join("");
      return `<section class="blk"><h2>Outline</h2><div class="defs">${rows}</div></section>`;
    }
    if (s.keys && s.keys.length) {
      return `<section class="blk"><h2>Top-level keys</h2>
        <div class="card mono" style="font-size:.86rem;color:var(--grey1)">${esc(s.keys.join("  ·  "))}</div></section>`;
    }
    return "";
  }

  function edgesBlock(n) {
    const rows = [];
    for (const e of n.edges_in || [])
      rows.push(`<div class="edge"><span class="org">${esc(e.origin)} ←</span><a href="#/${esc(e.target)}">${esc(e.target)}</a></div>`);
    for (const e of n.edges_out || [])
      rows.push(`<div class="edge"><span class="org">→ ${esc(e.origin)}</span><a href="#/${esc(e.target)}">${esc(e.target)}</a></div>`);
    if (!rows.length) return "";
    return `<section class="blk"><h2>Connections</h2><div class="edges">${rows.join("")}</div></section>`;
  }

  function sourceBlock(n) {
    if (!n.source) return "";
    const line = n.prose_line || 0;
    const span = n.prose ? n.prose.split(" ").length / 8 : 0;
    const lines = n.source.split("\n").map((raw, i) => {
      const no = i + 1;
      const inProse = line && no >= line && no <= line + span + 2;
      const html = esc(raw) || "&nbsp;";
      return inProse ? `<span class="hl">${html}</span>` : html;
    });
    return `<section class="blk"><h2>Source · ${n.loc} lines</h2>
      <pre class="src">${lines.join("\n")}</pre></section>`;
  }

  function childrenBlock(n) {
    if (!n.children || !n.children.length) return "";
    const kids = n.children.map((c) => {
      const cn = DATA.nodes[c];
      const dir = cn && cn.kind === "dir";
      return `<div class="kid" data-path="${esc(c)}">
        <span class="mark ${dir ? "" : "f"}">${dir ? "▸" : "·"}</span>
        <span class="nm">${esc(nameOf(c))}</span></div>`;
    }).join("");
    return `<section class="blk"><h2>Contents · ${n.children.length}</h2>
      <div class="kids">${kids}</div></section>`;
  }

  // ── detail: root dashboard ───────────────────────────────────────────────

  function renderRoot() {
    const s = DATA.stats;
    const pct = ((100 * s.covered) / s.files).toFixed(1);
    const hosts = Object.keys(DATA.machines);
    const caps = hosts.length ? Object.keys(DATA.machines[hosts[0]].caps).sort() : [];
    const capRows = caps.map((c) => {
      const cells = hosts.map((h) => {
        const on = DATA.machines[h].caps[c];
        return `<td class="${on ? "on" : "off"}">${on ? "yes" : "no"}</td>`;
      }).join("");
      return `<tr><td>${esc(c)}</td>${cells}</tr>`;
    }).join("");

    const entries = [
      ["flake.nix", "inputs and the mkHost fold to darwinConfigurations"],
      ["lib/machines.nix", "the complete per-host capability table"],
      ["modules/home/dotfiles.nix", "the out-of-store symlink map"],
      ["Justfile", "every build, sync and check recipe"],
      ["CLAUDE.md", "the architecture document agents read"],
      ["scripts/build-site.py", "the pipeline that generated this page"],
    ].filter(([p]) => DATA.nodes[p]).map(([p, why]) =>
      `<div class="edge"><span class="org" style="min-width:0"></span>
        <a href="#/${esc(p)}">${esc(p)}</a>
        <span style="color:var(--grey0);font-size:.84rem">${esc(why)}</span></div>`
    ).join("");

    el("detail").innerHTML = `
      ${crumbs("")}
      <h1>Repo Atlas</h1>
      <div class="facts">every page derived from the working tree</div>

      <div class="stats">
        <div class="stat"><div class="v">${s.files}</div><div class="t">tracked files in ${s.dirs} directories</div></div>
        <div class="stat"><div class="v">${s.covered}</div><div class="t">explained with no model, ${pct}% of the tree</div></div>
        <div class="stat y"><div class="v">${s.queue_files + s.queue_dirs}</div><div class="t">nodes queued for synthesis</div></div>
        <div class="stat b"><div class="v">${s.edges}</div><div class="t">edges derived from Justfile, mkLinks and CI</div></div>
      </div>

      <section class="blk"><h2>Where the knowledge comes from</h2>
        <div class="defs">
          <div class="def"><div class="sig"><span class="nm">T1</span> authored prose</div>
            <div class="doc">${s.with_prose} files carry a docstring or header comment block, read verbatim.</div></div>
          <div class="def"><div class="sig"><span class="nm">T2</span> doc binding</div>
            <div class="doc">${s.with_binding} files are named in CLAUDE.md, README.md or docs, and their sentences are quoted here.</div></div>
          <div class="def"><div class="sig"><span class="nm">T3</span> synthesis</div>
            <div class="doc">${s.fresh} fresh, ${s.stale} stale, ${s.missing} not yet written. Stale prose is suppressed, never shown.</div></div>
        </div>
      </section>

      <section class="blk"><h2>Start here</h2><div class="edges">${entries}</div></section>

      <section class="blk"><h2>Capability table</h2>
        <div class="card" style="padding:0;overflow-x:auto">
          <table class="captable"><thead><tr><th>capability</th>
            ${hosts.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead>
            <tbody>${capRows}</tbody></table></div>
        <p class="note" style="margin-top:10px">Every module gates on one of these or on
          <code>identity</code>. Each module page resolves its gates to the hosts above.</p>
      </section>`;
  }

  // ── detail: dispatch ─────────────────────────────────────────────────────

  function renderDetail() {
    const path = decodeURIComponent(location.hash.slice(2) || "");
    if (!path) return renderRoot();
    const n = DATA.nodes[path];
    if (!n) {
      el("detail").innerHTML = `${crumbs(path)}<h1>Not found</h1>
        <p class="note">No tracked node at that path. <a href="#/">Back to the root</a>.</p>`;
      return;
    }

    const facts = n.kind === "dir"
      ? `directory · ${n.children.length} entries`
      : `${n.lang} · ${n.loc} lines · ${bytes(n.size)}`;

    const excluded = n.excluded
      ? `<section class="blk"><div class="card"><p class="note">
           Classified <strong>${esc(n.excluded)}</strong>: real repository content, but it carries
           no authored meaning, so it is kept out of the synthesis queue.</p></div></section>`
      : "";

    el("detail").innerHTML =
      crumbs(path) +
      `<h1>${esc(n.name)}</h1><div class="facts">${esc(facts)}</div>` +
      tierPills(n) + excluded +
      gatesBlock(n) + proseBlock(n) + bindingBlock(n) + synthesisBlock(n) +
      childrenBlock(n) + defsBlock(n) + edgesBlock(n) + sourceBlock(n);
    el("detail").parentElement.scrollTop = 0;
  }

  // ── search ───────────────────────────────────────────────────────────────

  let paths = [], hits = [], cursor = -1;

  /** Subsequence match, scoring path-segment boundaries above mid-token hits. */
  function score(path, q) {
    const lower = path.toLowerCase();
    let i = 0, points = 0;
    const marks = [];
    for (const ch of q) {
      const at = lower.indexOf(ch, i);
      if (at < 0) return null;
      const boundary = at === 0 || "/-_.".includes(lower[at - 1]);
      points += boundary ? 9 : at === i ? 4 : 1;
      marks.push(at);
      i = at + 1;
    }
    if (lower.slice(lower.lastIndexOf("/") + 1).startsWith(q)) points += 24;
    return { points: points - path.length * 0.04, marks };
  }

  function search(q) {
    const list = el("rlist"), box = el("results");
    q = q.trim().toLowerCase();
    if (!q) { box.classList.remove("open"); el("q").setAttribute("aria-expanded", "false"); hits = []; return; }
    hits = [];
    for (const p of paths) {
      const s = score(p, q);
      if (s) hits.push({ path: p, ...s });
    }
    hits.sort((a, b) => b.points - a.points);
    hits = hits.slice(0, 40);
    cursor = hits.length ? 0 : -1;
    list.innerHTML = hits.map((h, i) => {
      let out = "", last = 0;
      for (const m of h.marks) {
        out += esc(h.path.slice(last, m)) + `<b>${esc(h.path[m])}</b>`;
        last = m + 1;
      }
      out += esc(h.path.slice(last));
      const kind = DATA.nodes[h.path].kind === "dir" ? "▸ " : "";
      return `<li class="${i === cursor ? "on" : ""}" data-path="${esc(h.path)}" role="option">${kind}${out}</li>`;
    }).join("") || `<li style="cursor:default">no match</li>`;
    box.classList.add("open");
    el("q").setAttribute("aria-expanded", "true");
  }

  function move(delta) {
    if (!hits.length) return;
    cursor = (cursor + delta + hits.length) % hits.length;
    [...el("rlist").children].forEach((li, i) => li.classList.toggle("on", i === cursor));
    const on = el("rlist").children[cursor];
    if (on) on.scrollIntoView({ block: "nearest" });
  }

  function go(path) {
    el("results").classList.remove("open");
    el("q").value = "";
    el("q").blur();
    el("tree").classList.remove("open");
    location.hash = `#/${path}`;
  }

  // ── wiring ───────────────────────────────────────────────────────────────

  function route() {
    const path = decodeURIComponent(location.hash.slice(2) || "");
    if (path) reveal(path);
    renderTree();
    renderDetail();
  }

  function boot(data) {
    DATA = data;
    paths = Object.keys(DATA.nodes).filter(Boolean).sort();
    for (const top of DATA.nodes[""].children) {
      if (DATA.nodes[top] && DATA.nodes[top].kind === "dir") open.add(top);
    }
    route();
    window.addEventListener("hashchange", route);

    el("tree").addEventListener("click", (e) => {
      const row = e.target.closest(".row");
      if (!row) return;
      const p = row.dataset.path;
      if (DATA.nodes[p].kind === "dir" && location.hash.slice(2) === p) {
        open.has(p) ? open.delete(p) : open.add(p);
        renderTree();
        return;
      }
      if (DATA.nodes[p].kind === "dir") open.add(p);
      location.hash = `#/${p}`;
    });

    el("detail").addEventListener("click", (e) => {
      const kid = e.target.closest(".kid");
      if (kid) go(kid.dataset.path);
    });

    el("q").addEventListener("input", (e) => search(e.target.value));
    el("rlist").addEventListener("click", (e) => {
      const li = e.target.closest("li[data-path]");
      if (li) go(li.dataset.path);
    });
    el("q").addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") { e.preventDefault(); move(1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); move(-1); }
      else if (e.key === "Enter" && cursor >= 0 && hits[cursor]) { e.preventDefault(); go(hits[cursor].path); }
      else if (e.key === "Escape") { el("results").classList.remove("open"); el("q").blur(); }
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "/" && document.activeElement !== el("q")) { e.preventDefault(); el("q").focus(); }
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest(".search")) el("results").classList.remove("open");
    });

    el("menu").addEventListener("click", () => el("tree").classList.toggle("open"));

    const setTheme = (t) => {
      document.documentElement.setAttribute("data-theme", t);
      el("theme").textContent = t === "dark" ? "Light" : "Dark";
      try { localStorage.setItem("atlas-theme", t); } catch (_) {}
    };
    let start = "dark";
    try { start = localStorage.getItem("atlas-theme") || start; } catch (_) {}
    if (start === "dark" && window.matchMedia &&
        window.matchMedia("(prefers-color-scheme: light)").matches) {
      let saved = null;
      try { saved = localStorage.getItem("atlas-theme"); } catch (_) {}
      if (!saved) start = "light";
    }
    setTheme(start);
    el("theme").addEventListener("click", () =>
      setTheme(document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark"));
  }

  fetch("data.json")
    .then((r) => r.json())
    .then(boot)
    .catch(() => {
      el("detail").innerHTML = `<h1>No payload</h1>
        <p class="note">Could not load <code>data.json</code>. Run <code>just site</code>,
        then serve this directory over HTTP: <code>python3 -m http.server -d site</code>.</p>`;
    });
})();
