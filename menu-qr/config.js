/* =====================================================================
   config.js · Conexión con TU base de datos de Supabase
   ---------------------------------------------------------------------
   Solo van aquí la URL del proyecto y la clave "anon public".
   La clave anon es pública por diseño: la seguridad la ponen las reglas
   RLS de supabase/schema.sql. NUNCA pongas aquí la clave "service_role".
   Si dejas supabaseUrl vacío, la app funciona en "Modo demo" (datos de
   ejemplo guardados solo en el teléfono). Lo más fácil: entra a
   panel/ → "Conectar mi base de datos" y descarga este archivo listo.
   ===================================================================== */
window.APP_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: "",
  demo: true   // true = si no hay URL, usar datos de ejemplo en el teléfono
};
