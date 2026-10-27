/* =====================================================================
   nucleo.js · Capa de datos con DOS adaptadores
   ---------------------------------------------------------------------
   - "supabase": tus datos viven en TU proyecto de Supabase (config.js).
   - "demo":     si config.js está vacío, todo se guarda en este
                 teléfono (localStorage) con datos de ejemplo.
   Las páginas usan siempre las mismas funciones (select, insert, update,
   remove, rpc, upload, auth, subscribe), sin importar el adaptador.
   No edites este archivo: la configuración va en config.js.
   ===================================================================== */
(function () {
  "use strict";
  const A = window.APP || {};
  const C0 = window.APP_CONFIG || {};
  const SCRIPT = document.currentScript && document.currentScript.src || location.href;
  const ROOT = SCRIPT.slice(0, SCRIPT.lastIndexOf("/") + 1);
  const SUPA_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/dist/umd/supabase.min.js";
  const OVR_KEY = A.prefix + "_cfg_local";

  let ovr = null;
  try { ovr = JSON.parse(localStorage.getItem(OVR_KEY) || "null"); } catch (e) { ovr = null; }
  const fileUrl = String(C0.supabaseUrl || "").trim(), fileKey = String(C0.supabaseAnonKey || "").trim();
  const usaOvr = !(fileUrl && fileKey) && !!(ovr && ovr.supabaseUrl && ovr.supabaseAnonKey);
  const URL_ = fileUrl && fileKey ? fileUrl.replace(/\/+$/, "") : usaOvr ? ovr.supabaseUrl : "";
  const KEY_ = fileUrl && fileKey ? fileKey : usaOvr ? ovr.supabaseAnonKey : "";
  const MODE = URL_ && KEY_ ? "supabase" : (C0.demo === false ? "none" : "demo");

  /* ---------------- Utilidades ---------------- */
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() :
    "10000000-1000-4000-8000-100000000000".replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)));
  const money = (n, cur) => (cur == null ? "$" : cur) + (isFinite(+n) ? +n : 0).toFixed(2);
  const money0 = (n, cur) => money(n, cur).replace(/\.00$/, "");
  const img = (p, fb) => !p ? (fb || "") : /^(https?:|data:|blob:)/.test(p) ? p : ROOT + p;
  const waNum = s => String(s || "").replace(/\D/g, "");
  const codigo = pre => (pre ? pre + "-" : "") + Date.now().toString(36).slice(-4).toUpperCase() + Math.random().toString(36).slice(2, 4).toUpperCase();
  const hoyISO = () => { const d = new Date(); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
  function loadScript(src) {
    return new Promise((ok, bad) => {
      if ([...document.scripts].some(s => s.src === src && s.dataset.ok)) return ok();
      const s = document.createElement("script"); s.src = src; s.async = true;
      s.onload = () => { s.dataset.ok = 1; ok(); }; s.onerror = () => bad(new Error("No se pudo cargar " + src.split("/")[2] + ". Revisa tu internet."));
      document.head.appendChild(s);
    });
  }
  function toast(t, ms) {
    let e = document.getElementById("nx-toast");
    if (!e) { e = document.createElement("div"); e.id = "nx-toast"; document.body.appendChild(e); }
    e.textContent = t; e.classList.add("show"); clearTimeout(e._t); e._t = setTimeout(() => e.classList.remove("show"), ms || 2600);
  }
  let actx;
  document.addEventListener("pointerdown", () => { try { actx = actx || new (window.AudioContext || window.webkitAudioContext)(); actx.resume(); } catch (e) {} });
  function ding() {
    try {
      actx = actx || new (window.AudioContext || window.webkitAudioContext)();
      [880, 1320].forEach((f, i) => {
        const o = actx.createOscillator(), g = actx.createGain(); o.type = "sine"; o.frequency.value = f; o.connect(g); g.connect(actx.destination);
        const t = actx.currentTime + i * .15; g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(.35, t + .02); g.gain.exponentialRampToValueAtTime(.0001, t + .35); o.start(t); o.stop(t + .4);
      });
      navigator.vibrate && navigator.vibrate([80, 40, 80]);
    } catch (e) {}
  }
  function notify(title, body) {
    ding(); toast(title + (body ? ": " + body : ""), 4000);
    try { if ("Notification" in window && Notification.permission === "granted" && document.hidden) new Notification(title, { body: body || "", icon: ROOT + "icon.png" }); } catch (e) {}
  }

  /* ---------------- Fotos: compresión en el navegador (WebP) ----------------
     Se redibuja en un canvas: queda WebP (o JPEG en Safari antiguo), sin EXIF/GPS. */
  function _cargar(file) { return new Promise((ok, bad) => { const u = URL.createObjectURL(file), im = new Image(); im.onload = () => { URL.revokeObjectURL(u); ok(im); }; im.onerror = () => { URL.revokeObjectURL(u); bad(new Error("Esa imagen no se pudo leer")); }; im.src = u; }); }
  const _blob = (c, t, q) => new Promise(ok => c.toBlob(ok, t, q));
  async function comprimir(file, opt) {
    const o = Object.assign(MODE === "supabase" ? { max: 1200, q: .8, kb: 190 } : { max: 640, q: .7, kb: 45 }, opt || {});
    if (!file || !/^image\//.test(file.type)) throw new Error("Elige una foto (JPG, PNG o WebP)");
    let src; try { src = await createImageBitmap(file, { imageOrientation: "from-image" }); } catch (e) { src = await _cargar(file); }
    let w = src.width, h = src.height; const k = Math.min(1, o.max / Math.max(w, h)); w = Math.round(w * k); h = Math.round(h * k);
    const c = document.createElement("canvas"); let b = null, q = o.q;
    for (let i = 0; i < 10; i++) {
      c.width = w; c.height = h; const x = c.getContext("2d"); x.fillStyle = "#fff"; x.fillRect(0, 0, w, h); x.drawImage(src, 0, 0, w, h);
      b = await _blob(c, "image/webp", q);
      if (!b || b.type !== "image/webp") b = await _blob(c, "image/jpeg", q);
      if (b.size <= o.kb * 1024) break;
      if (q > .5) q -= .1; else { w = Math.round(w * .85); h = Math.round(h * .85); }
    }
    if (b.size > 199 * 1024) throw new Error("La foto sigue muy pesada; prueba con otra");
    return b;
  }
  const blobToDataURL = b => new Promise(ok => { const r = new FileReader(); r.onload = () => ok(r.result); r.readAsDataURL(b); });

  /* ---------------- Errores en español ---------------- */
  function errES(e) {
    const m = String(e && (e.message || e.error_description || e.msg) || e || "");
    const code = e && e.code || "";
    let t = m, c = code;
    if (code === "23505" || /duplicate key/i.test(m)) { t = "Ese registro ya existe (por ejemplo, una hora ya reservada)."; c = "23505"; }
    else if (code === "42501" || /row-level security|permission denied/i.test(m)) { t = "No tienes permiso para hacer eso. Inicia sesión como dueño."; c = "42501"; }
    else if (code === "PGRST205" || code === "42P01" || /Could not find the table|does not exist/i.test(m)) { t = "Faltan las tablas en tu base de datos. Pega el archivo schema.sql en Supabase."; c = "NO_TABLES"; }
    else if (/Invalid login credentials/i.test(m)) { t = "Correo o clave incorrectos."; c = "LOGIN"; }
    else if (/Email not confirmed/i.test(m)) { t = "Ese correo no está confirmado. En Supabase marca “Auto Confirm User” al crearlo."; c = "LOGIN"; }
    else if (/Invalid API key|No API key|JWT/i.test(m)) { t = "La clave anon no es válida. Cópiala de nuevo desde Supabase."; c = "KEY"; }
    else if (/Failed to fetch|NetworkError|Load failed|network/i.test(m)) { t = "Sin conexión con la base de datos. Revisa tu internet."; c = "NET"; }
    const er = new Error(t); er.code = c; er.raw = m; return er;
  }

  /* ---------------- Adaptador LOCAL (modo demo) ---------------- */
  function Local() {
    const K = t => A.prefix + "_demo_" + t, VK = A.prefix + "_demo_version", SK = A.prefix + "_demo_sesion";
    if (localStorage.getItem(VK) !== String(A.seedVersion || 1)) {
      Object.keys(A.seed || {}).forEach(t => localStorage.setItem(K(t), JSON.stringify(A.seed[t])));
      localStorage.setItem(VK, String(A.seedVersion || 1));
    }
    const read = t => { try { return JSON.parse(localStorage.getItem(K(t)) || "[]"); } catch (e) { return []; } };
    const subs = {};
    const bc = "BroadcastChannel" in window ? new BroadcastChannel(A.prefix + "_demo") : null;
    const fire = ev => (subs[ev.t] || []).forEach(f => { try { f(ev); } catch (e) { console.warn(e); } });
    if (bc) bc.onmessage = e => fire(e.data);
    function write(t, rows, ev) {
      try { localStorage.setItem(K(t), JSON.stringify(rows)); }
      catch (e) { throw new Error("La memoria de este teléfono se llenó (modo demo). Borra algunas fotos o productos."); }
      const msg = Object.assign({ t }, ev || {}); fire(msg); try { bc && bc.postMessage(msg); } catch (e) {}
    }
    const match = (r, m) => Object.keys(m || {}).every(k => r[k] === m[k]);
    const cmp = (order) => (a, b) => { for (const [c, asc] of order) { const x = a[c], y = b[c]; if (x == y) continue; const r = (x == null ? -1 : y == null ? 1 : x > y ? 1 : -1); return asc === false ? -r : r; } return 0; };
    const clone = x => JSON.parse(JSON.stringify(x));
    function checkUnique(t, rows) { const u = (A.unique || {})[t]; if (!u) return; const seen = new Set(); rows.forEach(r => { const k = u(r); if (k == null) return; if (seen.has(k)) { const e = new Error("duplicate key"); e.code = "23505"; throw errES(e); } seen.add(k); }); }
    const sesion = () => { try { return JSON.parse(localStorage.getItem(SK) || "null"); } catch (e) { return null; } };
    return {
      modo: "demo",
      async select(t, o) {
        o = o || {}; let r = read(t).filter(x => match(x, o.eq));
        if (o.gte) r = r.filter(x => Object.keys(o.gte).every(k => x[k] >= o.gte[k]));
        if (o.order) r.sort(cmp(o.order)); if (o.limit) r = r.slice(0, o.limit); return clone(r);
      },
      async insert(t, row) {
        const rows = read(t), add = (Array.isArray(row) ? row : [row]).map(x => Object.assign({ creado: new Date().toISOString() }, clone(x)));
        if (A.beforeInsert && A.beforeInsert[t]) add.forEach(x => A.beforeInsert[t](x, read));
        const all = rows.concat(add); checkUnique(t, all); write(t, all, { tipo: "insert", row: add[0] });
      },
      async update(t, m, patch) { const rows = read(t); let last = null; rows.forEach(r => { if (match(r, m)) { Object.assign(r, clone(patch)); last = r; } }); checkUnique(t, rows); write(t, rows, { tipo: "update", row: last }); },
      async upsert(t, row, keys) { const rows = read(t), m = {}; (keys || ["id"]).forEach(k => m[k] = row[k]); const i = rows.findIndex(r => match(r, m)); if (i >= 0) Object.assign(rows[i], clone(row)); else rows.push(Object.assign({ creado: new Date().toISOString() }, clone(row))); checkUnique(t, rows); write(t, rows, { tipo: i >= 0 ? "update" : "insert", row }); },
      async remove(t, m) { write(t, read(t).filter(r => !match(r, m)), { tipo: "delete" }); },
      async rpc(n, args) { const f = (A.localRpc || {})[n]; if (!f) throw new Error("Función no disponible en modo demo: " + n); return f(this, args || {}); },
      async upload(blob) { return blobToDataURL(blob); },
      async removeFile() {},
      async esDueno() { return true; },
      auth: {
        async login(email, pass) {
          if (String(email).trim().toLowerCase() === "demo@demo.com" && pass === "demo123") { const u = { id: "demo-user", email: "demo@demo.com" }; localStorage.setItem(SK, JSON.stringify(u)); return u; }
          const e = new Error("Correo o clave incorrectos. En modo demo usa demo@demo.com / demo123"); e.code = "LOGIN"; throw e;
        },
        async user() { return sesion(); },
        async logout() { localStorage.removeItem(SK); }
      },
      subscribe(t, cb) { (subs[t] = subs[t] || []).push(cb); return () => { subs[t] = (subs[t] || []).filter(f => f !== cb); }; },
      reset() { Object.keys(localStorage).filter(k => k.indexOf(A.prefix + "_demo_") === 0 && k !== SK).forEach(k => localStorage.removeItem(k)); }
    };
  }

  /* ---------------- Adaptador SUPABASE (tu base de datos) ---------------- */
  async function Supa() {
    await loadScript(SUPA_CDN);
    const sb = window.supabase.createClient(URL_, KEY_, { auth: { persistSession: true, autoRefreshToken: true, storageKey: A.prefix + "-auth" } });
    const pub = URL_ + "/storage/v1/object/public/" + A.bucket + "/";
    const run = async q => { let r; try { r = await q; } catch (e) { throw errES(e); } if (r.error) throw errES(r.error); return r.data; };
    return {
      modo: "supabase", sb,
      async select(t, o) {
        o = o || {}; let q = sb.from(t).select(o.cols || "*");
        Object.keys(o.eq || {}).forEach(k => { q = q.eq(k, o.eq[k]); });
        Object.keys(o.gte || {}).forEach(k => { q = q.gte(k, o.gte[k]); });
        (o.order || []).forEach(([c, asc]) => { q = q.order(c, { ascending: asc !== false, nullsFirst: false }); });
        if (o.limit) q = q.limit(o.limit);
        return (await run(q)) || [];
      },
      insert: (t, row) => run(sb.from(t).insert(row)),
      update: (t, m, patch) => run(sb.from(t).update(patch).match(m)),
      upsert: (t, row, keys) => run(sb.from(t).upsert(row, { onConflict: (keys || ["id"]).join(",") })),
      remove: (t, m) => run(sb.from(t).delete().match(m)),
      rpc: (n, a) => run(sb.rpc(n, a || {})),
      async upload(blob) {
        const ext = blob.type === "image/webp" ? "webp" : "jpg", path = "f/" + uid() + "." + ext;
        await run(sb.storage.from(A.bucket).upload(path, blob, { cacheControl: "31536000", contentType: blob.type, upsert: false }));
        return pub + path;
      },
      async removeFile(u) { if (A.bucket && u && String(u).indexOf(pub) === 0) { try { await sb.storage.from(A.bucket).remove([String(u).slice(pub.length)]); } catch (e) {} } },
      async esDueno() { if (!A.ownerRpc) return true; return !!(await run(sb.rpc(A.ownerRpc))); },
      auth: {
        async login(email, pass) { const d = await run(sb.auth.signInWithPassword({ email: String(email).trim(), password: pass })); return d.user; },
        async user() { const { data } = await sb.auth.getSession(); return data && data.session ? data.session.user : null; },
        async logout() { try { await sb.auth.signOut(); } catch (e) {} }
      },
      subscribe(t, cb) {
        const ch = sb.channel("rt-" + t + "-" + Math.random().toString(36).slice(2, 7))
          .on("postgres_changes", { event: "*", schema: "public", table: t }, p => cb({ t, tipo: String(p.eventType).toLowerCase(), row: p.new }))
          .subscribe();
        return () => sb.removeChannel(ch);
      }
    };
  }

  let _db = null;
  function listo() {
    if (!_db) _db = MODE === "supabase" ? Supa() : MODE === "demo" ? Promise.resolve(Local()) : Promise.reject(Object.assign(new Error("Esta app aún no está conectada a su base de datos."), { code: "NO_CONFIG" }));
    return _db;
  }

  /* ---------------- Estilos mínimos compartidos ---------------- */
  const css = document.createElement("style");
  css.textContent = `#nx-toast{position:fixed;left:50%;bottom:24px;transform:translate(-50%,40px);opacity:0;max-width:92vw;background:linear-gradient(135deg,#f7e48c,#d4af37 48%,#a9851f);color:#1b1305;font:600 13.5px/1.35 Poppins,system-ui,sans-serif;padding:10px 18px;border-radius:999px;transition:.3s;z-index:9999;box-shadow:0 10px 30px rgba(0,0,0,.5);pointer-events:none;text-align:center}
#nx-toast.show{opacity:1;transform:translate(-50%,0)}
.nx-demo{position:relative;z-index:200;display:flex;gap:8px;align-items:center;justify-content:center;padding:7px 12px;font:600 11.5px/1.3 Poppins,system-ui,sans-serif;color:#1b1305;background:linear-gradient(135deg,#f7e48c,#d4af37 55%,#b8932a);text-align:center}
.nx-demo a{color:#1b1305;text-decoration:underline}
.nx-off{max-width:420px;margin:60px auto;padding:26px;border:1px solid rgba(212,175,55,.5);border-radius:22px;text-align:center;color:#f5edd9;font-family:Poppins,system-ui,sans-serif;background:#130f09}
.nx-off h2{font-family:'Playfair Display',Georgia,serif;font-size:24px;margin-bottom:8px}.nx-off p{color:#a99d82;font-size:14px}.nx-off a{color:#f3d97a}`;
  document.head.appendChild(css);
  function bannerDemo(extra) {
    if (MODE !== "demo" || document.querySelector(".nx-demo")) return;
    const b = document.createElement("div"); b.className = "nx-demo";
    b.innerHTML = "🧪 Modo demo · los cambios se guardan solo en este teléfono" + (extra || "");
    document.body.insertBefore(b, document.body.firstChild);
  }
  function pantallaSinConexion(panelHref) {
    document.body.innerHTML = `<div class="nx-off"><h2>App sin conectar</h2><p>Esta app aún no está conectada a su base de datos.</p><p style="margin-top:12px">Si eres el dueño, <a href="${panelHref || "panel/"}">entra al panel</a> y toca “Conectar mi base de datos”.</p></div>`;
  }

  window.Nucleo = {
    MODE, ROOT, URL: URL_, KEY: KEY_, APP: A, usaOverride: usaOvr, SUPA_CDN,
    listo, loadScript, errES, comprimir, $, $$, esc, uid, money, money0, img, waNum, codigo, hoyISO, toast, ding, notify, bannerDemo, pantallaSinConexion,
    setOverride(u, k) { localStorage.setItem(OVR_KEY, JSON.stringify({ supabaseUrl: u, supabaseAnonKey: k })); },
    clearOverride() { localStorage.removeItem(OVR_KEY); }
  };
})();
