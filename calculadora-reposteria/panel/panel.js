/* =====================================================================
   panel.js · Estructura común del panel del dueño
   (inicio de sesión, asistente "Conectar mi base de datos", revisión de
   tablas, pestañas y ayudas para formularios y fotos).
   No edites este archivo: la configuración va en config.js.
   ===================================================================== */
(function () {
  "use strict";
  const N = window.Nucleo, A = N.APP, { $, $$, esc } = N;
  const P = window.Panel = { db: null, user: null, tab: null, def: null, ajustes: {} };
  const root = () => document.getElementById("root");
  const ref = u => { try { return new URL(u).hostname.split(".")[0]; } catch (e) { return ""; } };
  const sqlUrl = u => "https://supabase.com/dashboard/project/" + ref(u) + "/sql/new";

  /* ---------- Ayudas de formulario ---------- */
  P.v = id => { const e = document.getElementById(id); return e ? (e.type === "checkbox" ? e.checked : e.value.trim()) : ""; };
  P.num = id => { const n = parseFloat(String(P.v(id)).replace(",", ".")); return isFinite(n) ? n : 0; };
  P.sw = (id, on, txt) => `<div class="swr"><span>${txt}</span><label class="sw" style="margin:0"><input type="checkbox" id="${id}" ${on ? "checked" : ""}><span></span></label></div>`;
  P.campo = (id, lbl, val, extra) => `<label for="${id}">${lbl}</label><input id="${id}" value="${esc(val == null ? "" : val)}" ${extra || ""}>`;
  /* Campo de foto: muestra la actual y permite cambiarla. La foto se comprime a WebP antes de subir. */
  P.foto = (id, lbl, actual, cuadrada) => `<label>${lbl}</label>
    <img class="prev ${cuadrada ? "sq" : ""}" id="${id}_pv" src="${esc(N.img(actual))}" style="${actual ? "" : "display:none"}" alt="">
    <input type="file" id="${id}" accept="image/*" data-actual="${esc(actual || "")}">
    ${actual ? `<button type="button" class="btn sm dark" style="margin-top:6px" data-quitar="${id}">Quitar foto</button>` : ""}`;
  P.bindFotos = (scope) => {
    $$("input[type=file]", scope).forEach(inp => inp.addEventListener("change", () => {
      const f = inp.files && inp.files[0], pv = document.getElementById(inp.id + "_pv");
      if (f && pv) { pv.src = URL.createObjectURL(f); pv.style.display = ""; }
    }));
    $$("[data-quitar]", scope).forEach(b => b.onclick = () => { const i = document.getElementById(b.dataset.quitar); i.dataset.actual = ""; i.value = ""; const pv = document.getElementById(i.id + "_pv"); if (pv) pv.style.display = "none"; b.remove(); });
  };
  /* Devuelve la URL final de la foto: sube la nueva (si eligieron una) o conserva la actual */
  P.leerFoto = async (id) => {
    const i = document.getElementById(id); if (!i) return "";
    const f = i.files && i.files[0];
    if (!f) return i.dataset.actual || "";
    const b = await N.comprimir(f);
    return P.db.upload(b);
  };
  P.ocupado = async (btn, fn) => {
    const t = btn ? btn.innerHTML : ""; if (btn) { btn.disabled = true; btn.innerHTML = "Guardando…"; }
    try { return await fn(); } catch (e) { N.toast("⚠️ " + (e.message || e), 4200); console.warn(e); }
    finally { if (btn && document.body.contains(btn)) { btn.disabled = false; btn.innerHTML = t; } }
  };
  P.modal = (html, bind) => {
    P.cerrar(); const m = document.createElement("div"); m.className = "modal"; m.id = "modal";
    m.innerHTML = `<div class="sh">${html}</div>`; m.addEventListener("click", e => { if (e.target === m) P.cerrar(); });
    document.body.appendChild(m); P.bindFotos(m); if (bind) bind(m); return m;
  };
  P.cerrar = () => { const m = document.getElementById("modal"); if (m) m.remove(); };
  P.confirmar = t => window.confirm(t);
  P.badge = (tab, n) => { const b = document.querySelector(`.tabs [data-tab="${tab}"] .bd`); if (b) b.textContent = n ? String(n) : ""; };
  P.descargar = (nombre, texto) => { const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([texto], { type: "text/javascript" })); a.download = nombre; document.body.appendChild(a); a.click(); setTimeout(() => a.remove(), 500); };
  P.copiar = async (t) => { try { await navigator.clipboard.writeText(t); N.toast("✓ Copiado"); } catch (e) { const ta = document.createElement("textarea"); ta.value = t; document.body.appendChild(ta); ta.select(); try { document.execCommand("copy"); N.toast("✓ Copiado"); } catch (x) { N.toast("Selecciona el texto y cópialo"); } ta.remove(); } };
  P.cargarAjustes = async () => { const r = await P.db.select(A.prefix + "_ajustes", { eq: { id: 1 } }); P.ajustes = (r[0] && r[0].datos) || {}; return P.ajustes; };
  P.guardarAjustes = async (datos) => { P.ajustes = Object.assign({}, P.ajustes, datos); await P.db.upsert(A.prefix + "_ajustes", { id: 1, datos: P.ajustes }, ["id"]); };

  /* ---------- Contenido de config.js ---------- */
  const configTexto = (u, k) => `/* =====================================================================
   config.js · Conexión con TU base de datos de Supabase
   ---------------------------------------------------------------------
   Solo van aquí la URL del proyecto y la clave "anon public".
   La clave anon es pública por diseño: la seguridad la ponen las reglas
   RLS de schema.sql. NUNCA pongas aquí la clave "service_role".
   Si dejas supabaseUrl vacío, la app funciona en "Modo demo".
   ===================================================================== */
window.APP_CONFIG = {
  supabaseUrl: "${u}",
  supabaseAnonKey: "${k}",
  demo: true   // true = si no hay URL, usar datos de ejemplo en el teléfono
};
`;

  /* ---------- Pantalla: SQL pendiente ---------- */
  async function textoSQL() {
    try { const r = await fetch(N.ROOT + "supabase/schema.sql", { cache: "no-store" }); if (r.ok) return await r.text(); } catch (e) {}
    return "-- No se pudo leer supabase/schema.sql. Ábrelo desde la carpeta de la app y copia todo su contenido.";
  }
  async function vistaSQL(url, alListo) {
    const sql = await textoSQL();
    root().innerHTML = `<div class="wrap" style="padding-top:22px;padding-bottom:40px"><div class="box">
      <h3>Falta crear las tablas</h3>
      <p class="mut small">La conexión funciona ✓, pero tu base de datos todavía está vacía. Hazlo una sola vez:</p>
      <ol class="steps"><li>Toca <b>Copiar SQL</b>.</li><li>Abre el <a href="${sqlUrl(url)}" target="_blank" rel="noopener">Editor SQL de Supabase ↗</a>.</li><li>Pega todo y toca <b>Run</b> (abajo a la derecha). Debe decir “Success”.</li><li>Vuelve aquí y toca <b>Ya lo pegué, revisar</b>.</li></ol>
      <div class="row"><button class="btn" id="cpSql">📋 Copiar SQL</button><a class="btn dark" href="${sqlUrl(url)}" target="_blank" rel="noopener">Abrir editor ↗</a></div>
      <button class="btn full" id="reSql">Ya lo pegué, revisar</button>
      <p class="mut small" style="margin-top:14px">Vista previa del archivo <b>supabase/schema.sql</b>:</p><div class="code" style="margin-top:6px">${esc(sql)}</div>
    </div></div>`;
    $("#cpSql").onclick = () => P.copiar(sql);
    $("#reSql").onclick = alListo;
  }

  /* ---------- Asistente: Conectar mi base de datos ---------- */
  P.conectar = function () {
    const ov = N.usaOverride ? { u: N.URL, k: N.KEY } : { u: "", k: "" };
    root().innerHTML = `<div class="wrap" style="padding-top:22px;padding-bottom:40px">
     <div class="box"><div class="logo-c">🔌</div><h2 class="t" style="text-align:center">Conectar mi <span class="gold">base de datos</span></h2>
      <p class="mut small" style="text-align:center">Tus productos, ajustes y pedidos se guardarán en tu propia cuenta gratis de Supabase.</p>
      <ol class="steps"><li>Crea una cuenta y un proyecto gratis en <a href="https://supabase.com/dashboard" target="_blank" rel="noopener">supabase.com ↗</a>.</li>
      <li>En tu proyecto ve a <b>Project Settings → API</b> (o <b>Data API</b>) y copia la <b>Project URL</b> y la clave <b>anon public</b> (también sirve la “publishable key”).</li>
      <li>Pégalas aquí abajo y toca <b>Probar conexión</b>.</li></ol>
      ${P.campo("cU", "Project URL", ov.u, 'placeholder="https://xxxxxxxx.supabase.co" inputmode="url" autocomplete="off"')}
      <label for="cK">Clave anon public</label><textarea id="cK" rows="3" placeholder="Pega aquí la clave anon public (texto largo) o sb_publishable_…" autocomplete="off" style="font-size:12.5px">${esc(ov.k)}</textarea>
      <p class="note">🔒 Nunca pegues la clave <b>service_role</b> ni la “secret key”: esas son privadas.</p>
      <button class="btn full" id="cTest">Probar conexión</button><div id="cOut"></div>
      <hr class="d"><a class="btn dark sm" href="./">← Volver</a>
     </div></div>`;
    $("#cTest").onclick = probar;
  };
  async function probar() {
    const out = $("#cOut"), btn = $("#cTest");
    let u = $("#cU").value.trim().replace(/\/+$/, "").replace(/\/rest\/v1$/, ""); const k = $("#cK").value.trim().replace(/\s+/g, "");
    if (!/^https:\/\/[a-z0-9-]+\.supabase\.(co|in)$/i.test(u) && !/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(u)) { out.innerHTML = `<p class="err">La URL debe verse así: https://abcdefgh.supabase.co</p>`; return; }
    if (k.length < 30) { out.innerHTML = `<p class="err">Pega la clave anon completa (es un texto largo).</p>`; return; }
    let rol = ""; try { rol = k.indexOf("e" + "yJ") === 0 ? atob((k.split(".")[1] || "").replace(/-/g, "+").replace(/_/g, "/")) : ""; } catch (e) { rol = ""; }
    if (/sb_secret_/.test(k) || /service_role/.test(rol)) { out.innerHTML = `<p class="err">⛔ Esa es la clave SECRETA (service_role). No la uses aquí: copia la clave “anon public”.</p>`; return; }
    btn.disabled = true; btn.textContent = "Probando…"; out.innerHTML = "";
    try {
      await N.loadScript(N.SUPA_CDN);
      const c = window.supabase.createClient(u, k, { auth: { persistSession: false } });
      const r = await c.from(A.prefix + "_ajustes").select("*").limit(1);
      if (r.error) {
        const e = N.errES(r.error);
        if (e.code === "NO_TABLES") { await vistaSQL(u, () => { P.conectar(); $("#cU").value = u; $("#cK").value = k; probar(); }); return; }
        throw e;
      }
      mostrarConfig(u, k);
    } catch (e) {
      const m = N.errES(e); out.innerHTML = `<p class="err">${esc(m.code === "NET" ? "No se pudo conectar con esa URL. Revisa que esté bien escrita y que el proyecto no esté pausado." : m.message)}</p>`;
    } finally { if (document.body.contains(btn)) { btn.disabled = false; btn.textContent = "Probar conexión"; } }
  }
  function mostrarConfig(u, k) {
    const txt = configTexto(u, k);
    root().innerHTML = `<div class="wrap" style="padding-top:22px;padding-bottom:40px"><div class="box">
      <div class="logo-c">✅</div><h2 class="t" style="text-align:center">¡Conexión <span class="gold">lista!</span></h2>
      <p class="mut small">Tu base de datos responde y las tablas existen. Ahora guarda la conexión en tu sitio:</p>
      <ol class="steps"><li>Toca <b>Descargar config.js</b>.</li><li>Sube ese archivo a la carpeta de esta app en GitHub (o Netlify), <b>reemplazando</b> el config.js que ya está. En GitHub: entra a la carpeta → <b>Add file → Upload files</b> → arrastra config.js → <b>Commit changes</b>.</li><li>Espera 1–2 minutos y recarga. Desde ese momento todos tus clientes verán tus datos.</li></ol>
      <button class="btn full" id="dl">⬇️ Descargar config.js</button>
      <div class="row" style="margin-top:8px"><button class="btn dark sm" id="cp">📋 Copiar texto</button><button class="btn dark sm" id="ya">Usar ya en este teléfono</button></div>
      <p class="mut small" style="margin-top:12px">Contenido de <b>config.js</b>:</p><div class="code" style="margin-top:6px">${esc(txt)}</div>
      <p class="note">“Usar ya en este teléfono” te deja entrar al panel ahora mismo, pero tus clientes solo verán tus datos cuando subas config.js.</p>
      <p class="mut small" style="margin-top:12px">Siguiente paso: crea tu usuario de dueño en Supabase → <b>Authentication → Users → Add user → Create new user</b> (marca “Auto Confirm User”). Con ese correo y clave entras al panel.</p>
    </div></div>`;
    $("#dl").onclick = () => P.descargar("config.js", txt);
    $("#cp").onclick = () => P.copiar(txt);
    $("#ya").onclick = () => { N.setOverride(u, k); location.href = location.pathname; };
  }

  /* ---------- Inicio de sesión ---------- */
  function vistaLogin(err) {
    const demo = N.MODE === "demo";
    root().innerHTML = `<div class="center"><div class="box">
      <div class="logo-c">${A.icono || "✨"}</div>
      <h2 class="t" style="text-align:center;margin-bottom:4px">Panel · <span class="gold">${esc(A.titulo || "")}</span></h2>
      <p class="mut small" style="text-align:center">${esc(A.loginSub || "Solo para el dueño del negocio")}</p>
      ${P.campo("lE", "Correo", demo ? "demo@demo.com" : "", 'type="email" autocomplete="username" inputmode="email"')}
      ${P.campo("lP", "Clave", demo ? "demo123" : "", 'type="password" autocomplete="current-password"')}
      <button class="btn full" id="lGo">Entrar</button>
      ${err ? `<p class="err">${esc(err)}</p>` : ""}
      ${demo ? `<p class="note">🧪 Demo: usuario <b>demo@demo.com</b> / clave <b>demo123</b><br>Los cambios se guardan solo en este teléfono.</p>
        <hr class="d"><p class="mut small" style="text-align:center">¿Ya tienes tu propia base de datos?</p><button class="btn dark full" id="lCon" style="margin-top:8px">🔌 Conectar mi base de datos</button>`
        : `<p class="mut small" style="margin-top:12px">Usa el correo y la clave del usuario que creaste en Supabase → Authentication → Users.</p>
        ${N.usaOverride ? `<button class="btn dark sm" id="lOff" style="margin-top:10px">Desconectar esta base de datos de este teléfono</button>` : ""}`}
      <p style="text-align:center;margin-top:14px"><a href="../" class="small">← Ver la página pública</a></p>
    </div></div>`;
    const go = async () => {
      const b = $("#lGo"); b.disabled = true; b.textContent = "Entrando…";
      try { P.user = await P.db.auth.login($("#lE").value, $("#lP").value); await entrar(); }
      catch (e) { vistaLogin(N.errES(e).message || e.message); }
    };
    $("#lGo").onclick = go; $("#lP").onkeydown = e => { if (e.key === "Enter") go(); };
    if ($("#lCon")) $("#lCon").onclick = P.conectar;
    if ($("#lOff")) $("#lOff").onclick = () => { N.clearOverride(); location.reload(); };
  }

  /* ---------- Después de iniciar sesión ---------- */
  async function entrar() {
    try { await P.db.select(P.def.tablaCheck || A.prefix + "_ajustes", { limit: 1 }); }
    catch (e) { if (e.code === "NO_TABLES") return vistaSQL(N.URL, () => location.reload()); throw e; }
    let dueno = true; try { dueno = await P.db.esDueno(); } catch (e) { if (e.code === "NO_TABLES") return vistaSQL(N.URL, () => location.reload()); throw e; }
    if (!dueno) {
      root().innerHTML = `<div class="center"><div class="box" style="text-align:center"><div class="logo-c">🔒</div><h3>Esta cuenta no es la dueña</h3>
        <p class="mut small">Este negocio ya tiene un dueño registrado. Entra con la cuenta del dueño.</p><button class="btn full" id="out">Cerrar sesión</button></div></div>`;
      $("#out").onclick = async () => { await P.db.auth.logout(); location.reload(); }; return;
    }
    if (P.def.alEntrar) await P.def.alEntrar();
    shell();
  }
  function shell() {
    const tabs = P.def.tabs;
    root().innerHTML = `<header class="top"><div class="wrap"><img class="lg" id="tLogo" alt="" src="${esc(N.img(P.ajustes.logo, N.ROOT + "icon.png"))}"><div class="sp"><b id="tNom">${esc(P.ajustes.nombre || P.ajustes.negocio || A.titulo)}</b><small>Panel · ${esc(P.user && P.user.email || "")}</small></div>
      <a class="ib" href="${esc(P.def.publico || "../")}" target="_blank" rel="noopener" title="Ver página pública">↗</a><button class="ib" id="tOut" title="Cerrar sesión">⎋</button></div></header>
      <main class="wrap" id="v"></main>
      <nav class="tabs">${tabs.map(t => `<button data-tab="${t.id}"><b>${t.ic}</b>${t.lbl}<span class="bd"></span></button>`).join("")}</nav>`;
    $("#tOut").onclick = async () => { await P.db.auth.logout(); location.href = location.pathname; };
    $$(".tabs button").forEach(b => b.onclick = () => P.ir(b.dataset.tab));
    const h = location.hash.slice(1); P.ir(tabs.some(t => t.id === h) ? h : tabs[0].id);
    if ("Notification" in window && Notification.permission === "default") document.addEventListener("pointerdown", () => { try { Notification.requestPermission(); } catch (e) {} }, { once: true });
  }
  P.ir = async (id) => {
    P.tab = id; history.replaceState(null, "", "#" + id);
    $$(".tabs button").forEach(b => b.classList.toggle("on", b.dataset.tab === id));
    const t = P.def.tabs.find(x => x.id === id), v = $("#v");
    v.innerHTML = `<p class="mut" style="padding:30px 0;text-align:center">Cargando…</p>`;
    try { await t.render(v); P.bindFotos(v); } catch (e) { console.warn(e); v.innerHTML = `<div class="box"><p class="err">${esc(N.errES(e).message)}</p><button class="btn sm" onclick="Panel.ir('${id}')">Reintentar</button></div>`; }
    window.scrollTo({ top: 0 });
  };
  P.refrescar = () => { if (P.tab) P.ir(P.tab); };
  P.refrescarTop = () => { const n = $("#tNom"), l = $("#tLogo"); if (n) n.textContent = P.ajustes.nombre || P.ajustes.negocio || A.titulo; if (l) l.src = N.img(P.ajustes.logo, N.ROOT + "icon.png"); };

  /* ---------- Arranque ---------- */
  P.iniciar = async function (def) {
    P.def = def;
    N.bannerDemo(' · <a href="#" id="bCon">Conectar mi base</a>');
    const bc = document.getElementById("bCon"); if (bc) bc.onclick = e => { e.preventDefault(); P.conectar(); };
    if (N.MODE === "none" || /[?&]conectar\b/.test(location.search)) return P.conectar();
    try { P.db = await N.listo(); } catch (e) { root().innerHTML = `<div class="center"><div class="box"><p class="err">${esc(e.message)}</p><button class="btn full" onclick="location.reload()">Reintentar</button></div></div>`; return; }
    try { P.user = await P.db.auth.user(); } catch (e) { P.user = null; }
    if (!P.user) return vistaLogin();
    try { await entrar(); } catch (e) { vistaLogin(N.errES(e).message); }
  };
})();
