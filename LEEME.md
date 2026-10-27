# Vendedor Automático · versión en línea (Supabase)

Sitio estático para GitHub Pages: **https://dunig3.github.io/conexi-n/vendedor/**
(tienda: `vendedor/tienda/?n=dulces&ref=ANA01` · panel: `vendedor/panel/?n=dulces` · promotor: `vendedor/promotor/?n=dulces`).
Todas las rutas son relativas: funciona igual en cualquier usuario/repositorio de GitHub Pages.

Demo: PIN del panel **0000** · promotores **ANA01 / 1234**, **LUIS02 / 1234** (dulces), **CARLA1 / 1234** (belleza).

## Qué cambió
- **Los datos ya no viven en el teléfono** (localStorage): ahora están en Supabase (proyecto *dunig3*), en tablas `va_*`. La tienda, el panel y los promotores se sincronizan entre dispositivos.
- `vendedor/core.js` se reescribió con **supabase-js v2** (CDN, versión fija 2.118.0). Conserva las mismas funciones (`N()`, `img()`, `money()`, `toast()`, `notify()`, `ding()`…), así que las páginas cambiaron poco y se ven igual.
- **Tiempo real**: el servidor emite un aviso (Broadcast de Supabase Realtime, sin datos personales) cuando hay un pedido, mensaje o cambio de estado; la página pide solo lo nuevo. Si Realtime no conecta, se usa un **sondeo ligero** (cada 20 s; cada 2 min con conexión) y también se refresca al volver a la pestaña. Esto reemplaza a BroadcastChannel.
- **Seguridad**
  - RLS activado en todas las tablas `va_*`. El público solo puede **leer** negocios, productos y métodos de pago.
  - Todo lo demás pasa por funciones `SECURITY DEFINER` que validan los datos en el servidor (largos, cantidades, que el producto exista; **el total se calcula con los precios del servidor**).
  - Los PIN se guardan con hash bcrypt (`pgcrypto crypt`). Entrar al panel o a la app del promotor devuelve un **token de 12 h** (en la base solo se guarda su hash SHA-256). Hay bloqueo tras varios PIN fallidos.
  - Anti-spam: límites por IP, por cliente y por negocio para pedidos, mensajes, códigos de cobro y subidas.
  - Cada cliente tiene un id secreto (UUID) en su teléfono: solo con él puede ver su chat y el estado de sus pedidos. El promotor ve sus pedidos sin teléfono ni dirección del cliente.
- **Imágenes**: se comprimen en el navegador antes de subir (WebP, máx. 800 px y ~80 KB para productos; portada 1200 px; comprobantes 1000 px). Al redibujar en canvas se borran los metadatos (EXIF/GPS). Bucket `va-imagenes` público, máx. 200 KB por archivo, solo WebP/JPEG, caché de 1 año. Para subir hace falta un **ticket de un solo uso** que da el servidor. Al cambiar o borrar la foto de un producto, **la foto vieja se borra**.
- **Nuevo** (pequeño): el cliente puede adjuntar una **foto del comprobante** (opcional) y ve el **estado en vivo** de sus pedidos dentro del chat; el dueño puede editar productos, cambiar su foto, cambiar la portada y ver el **uso del plan gratis** (en Ajustes). Se quitó "Reiniciar demo", porque los datos ahora están en la nube.
- **Service worker** (`sw.js`, va-v3): no cachea nunca la API de Supabase; las fotos del bucket sí se guardan en caché local (ahorra transferencia).
- El catálogo se guarda en caché en el teléfono (5 min) y aparece al instante.

## Estrategia para quedarse SIEMPRE en el plan gratis
| Límite gratis | Qué hacemos |
|---|---|
| 500 MB de base de datos | Tipos compactos y pocos índices. Tarea diaria `va-mantenimiento` (pg_cron, 07:17 UTC): borra chat de más de 60 días, códigos de cobro de más de 30 días, sesiones y contadores viejos, y **archiva pedidos cerrados de más de 6 meses** en un resumen mensual por promotor (`va_resumen`), así no se pierden las cifras del ranking ni del total cobrado. Si la base pasa de 400 MB, la limpieza se hace más fuerte (chat 20 días, pedidos 90 días). Nunca se archiva efectivo que el promotor todavía no ha entregado. |
| 1 GB de Storage | Fotos de ~20-80 KB. Los comprobantes se borran a los 30 días; las subidas huérfanas, al día siguiente. Las fotos reemplazadas se borran al instante. Máximo 200 productos por negocio. |
| 5 GB de transferencia | Caché de 1 año en las fotos, más el caché del service worker y el del catálogo. El tiempo real solo manda avisos diminutos y luego se piden solo los cambios. |
| Pausa tras 7 días sin uso | `.github/workflows/supabase-keepalive.yml` consulta `va_ping` cada 2 días con la clave pública anon. Además reactiva su propio workflow, porque GitHub apaga los workflows programados tras 60 días sin commits. |

La función `va_uso()` informa el tamaño de la base y de Storage. Se ve en el panel → Ajustes → "Ver uso del plan gratis".

## Archivos
- `vendedor/core.js` · `vendedor/tienda/index.html` · `vendedor/panel/index.html` · `vendedor/promotor/index.html` · `vendedor/sw.js` · `vendedor/index.html` (solo un texto)
- `.github/workflows/supabase-keepalive.yml`
- `supabase/schema.sql` (todo el esquema: tablas, RLS, funciones, bucket, cron) · `supabase/seed.sql` (demo) · `supabase/prueba-api.sh` (prueba con curl)

## Publicar
1. Sube esta carpeta al repo `dunig3/conexi-n` y activa **Settings → Pages → Deploy from branch → main / (root)**.
2. (Opcional) Crea los secretos `SUPABASE_URL` y `SUPABASE_ANON_KEY`; si no existen, el workflow usa los valores públicos que ya trae.
3. Revisa **Actions → Supabase keep-alive → Run workflow** una vez para confirmar que pasa.

## Notas
- La clave `anon` que va en `core.js` es pública por diseño; la protección real está en RLS y en las funciones. La clave `service_role` **no** está en el sitio: solo está guardada en Supabase Vault (`va_service_key`), donde el servidor la usa para borrar imágenes.
- Para un negocio nuevo, inserta una fila en `va_negocios`, otra en `va_negocio_priv` (con el PIN en `crypt`) y sus `va_cuentas` (copia el patrón de `seed.sql`).
- Las tablas de la otra app en *dunig3* no se tocaron.
