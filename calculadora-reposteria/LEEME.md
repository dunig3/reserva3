# Calculadora de precios para reposteras

Calcula a cuánto vender cada torta: costo, margen de ganancia y precio por porción. Con una cuenta, guardas **tu lista de ingredientes con precios** y **tus recetas**: si cambia el precio de la harina, lo cambias una sola vez y todas tus recetas se recalculan. Sin iniciar sesión también funciona (guarda en el teléfono).

Todo se ve en el estilo negro y dorado, funciona en el teléfono y **tus datos viven en tu propia base de datos gratis de Supabase** (nada de tu negocio queda escrito en el código).

## Qué trae esta carpeta

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La página pública para tus clientes. |
| `panel/index.html` | Tu panel de control (con usuario y clave). |
| `config.js` | **El único archivo que se edita**: la dirección (URL) de tu Supabase y tu clave *anon public*. |
| `supabase/schema.sql` | Crea tus tablas y reglas de seguridad. Se pega una sola vez en Supabase. |
| `app.js`, `nucleo.js`, `panel/panel.js`, `panel/panel.css`, `img/`, `icon.png`, `manifest.json` | El funcionamiento de la app. No hace falta tocarlos. |

## Pruébala primero (modo demo)

Si `config.js` está vacío, la app funciona en **Modo demo**: trae datos de ejemplo y todo se guarda solo en ese teléfono. Entra a `panel/` con:

- Usuario: **demo@demo.com**
- Clave: **demo123**

## Ponla a funcionar con TU base de datos (unos 15 minutos)

### 1. Crea tu proyecto gratis en Supabase
1. Entra a **https://supabase.com** y toca **Start your project**. Regístrate (puedes usar tu cuenta de Google o GitHub).
2. Toca **New project**. Ponle un nombre (ej: *mi-negocio*), inventa una contraseña para la base de datos (guárdala) y elige la región más cercana (ej: *East US*). Toca **Create new project** y espera 1–2 minutos.

### 2. Crea las tablas (copiar y pegar)
1. En el menú de la izquierda entra a **SQL Editor** → **New query**.
2. Abre el archivo `supabase/schema.sql` de esta carpeta, copia **todo** su contenido y pégalo.
3. Toca **Run** (abajo a la derecha). Debe decir **Success. No rows returned**.

> El panel también te muestra este SQL con un botón **Copiar SQL** y el enlace directo al editor si detecta que faltan las tablas.

### 3. Crea tu usuaria
1. Menú izquierdo → **Authentication** → **Users** → **Add user** → **Create new user**.
2. Escribe tu correo y una clave, marca **Auto Confirm User** y toca **Create user**.

3. **Recomendado:** en **Authentication → Sign In / Providers** desactiva **Allow new users to sign up**, así nadie más puede crearse una cuenta en tu proyecto.

### 4. Conecta la app (la forma fácil)
1. Publica la carpeta (paso 5) o ábrela en tu navegador, entra a `panel/` y toca **🔌 Conectar mi base de datos**.
2. En Supabase ve a **Project Settings → API** (o **Data API / API Keys**) y copia:
   - **Project URL** (se ve así: `https://abcdefgh.supabase.co`)
   - la clave **anon public** (o la **publishable key**).
3. Pégalas en el panel y toca **Probar conexión**. Si todo está bien, toca **⬇️ Descargar config.js**.
4. Sube ese `config.js` a tu sitio **reemplazando** el que está en esta carpeta.

**¿Prefieres hacerlo a mano?** Abre `config.js` con el Bloc de notas y pega tus datos entre las comillas:
```js
window.APP_CONFIG = {
  supabaseUrl: "https://abcdefgh.supabase.co",
  supabaseAnonKey: "tu-clave-anon-public",
  demo: true
};
```

> 🔒 La clave **anon public** es pública por diseño: la seguridad la ponen las reglas (RLS) de `schema.sql`. **Nunca** pongas la clave **service_role** ni la **secret key** en ningún archivo.

### 5. Publícala gratis
**Opción A · GitHub Pages**
1. Crea una cuenta en **https://github.com** → **New repository** (público) → por ejemplo `mi-negocio`.
2. Toca **uploading an existing file** y arrastra **el contenido de esta carpeta** (con sus subcarpetas `panel`, `img` y `supabase`). Toca **Commit changes**.
3. Ve a **Settings → Pages** → *Branch*: **main** y carpeta **/ (root)** → **Save**. En 1–2 minutos tu app estará en `https://TU-USUARIO.github.io/mi-negocio/`.

**Opción B · Netlify**
1. Entra a **https://app.netlify.com/drop** y arrastra esta carpeta completa. Listo: te da una dirección que puedes compartir.

Para cambiar `config.js` después: en GitHub entra al archivo → ✏️ (editar) → pega → **Commit changes**. En Netlify vuelve a arrastrar la carpeta.

### 6. Úsala
1. Abre `tu-sitio/panel/`, entra con tu usuaria que creaste.
2. Página pública para compartir: `tu-sitio/calculadora-reposteria/`

## El panel

- **Ingredientes**: nombre, cuánto trae el paquete (g, kg, ml, l o unidades) y su precio. Muestra el costo por gramo/unidad.
- **Recetas**: tus recetas guardadas con costo, precio por porción y precio de la torta siempre al día. Ábrelas en la calculadora, duplícalas o bórralas.
- **Ajustes**: nombre de tu negocio, moneda, redondeo del precio por porción, margen y porciones por defecto, WhatsApp opcional.

Las fotos se **comprimen solas** en el teléfono (WebP de máximo ~1200 px y menos de 200 KB) antes de subirse, para que todo cargue rápido y no gastes el espacio gratis de Supabase.

## Seguridad (qué protege schema.sql)

- Todas las tablas tienen **RLS activado**. Prefijo de las tablas: `rep_` (`rep_ajustes`, `rep_ingredientes`, `rep_recetas`), así varias apps pueden convivir en el mismo proyecto de Supabase.
- Cada usuaria ve y edita **solo sus propios** ingredientes, recetas y ajustes. Las personas sin sesión no pueden leer nada de la base de datos.

- En la app no hay ninguna clave secreta.

## Preguntas frecuentes

- **El panel dice “Faltan las tablas”**: repite el paso 2 (pegar `schema.sql` y tocar Run). Se puede ejecutar varias veces sin borrar nada.
- **“Correo o clave incorrectos”**: revisa el usuario en Authentication → Users y que tenga *Auto Confirm User*.

- **Mi proyecto de Supabase se pausó**: los proyectos gratis se pausan tras 7 días sin uso. Entra a supabase.com y toca **Restore project**.
- **¿Puedo poner varias apps en el mismo Supabase?** Sí: cada app usa su propio prefijo de tablas. Pega el `schema.sql` de cada una.
