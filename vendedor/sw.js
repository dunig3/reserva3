/* Service worker — Vendedor Automático (versión en línea)
   - Páginas del sitio: red primero, caché como respaldo sin conexión.
   - API de Supabase (REST, RPC, Realtime, subidas): NUNCA se cachea.
   - Fotos públicas del bucket (rutas nuevas en cada cambio = inmutables): caché primero → ahorra egress. */
const C='va-v3',CI='va-img-v1',MAX_IMG=150;
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(['./','./style.css','./core.js','./icon.png','./tienda/','./panel/','./promotor/'])).catch(()=>{}));self.skipWaiting()});
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&x!==CI).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
async function recortar(){const c=await caches.open(CI),k=await c.keys();for(let i=0;i<k.length-MAX_IMG;i++)await c.delete(k[i])}
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
 if(u.hostname.endsWith('.supabase.co')){
  if(u.pathname.startsWith('/storage/v1/object/public/')){   /* imágenes públicas: caché primero */
   e.respondWith(caches.open(CI).then(c=>c.match(r).then(h=>h||fetch(r).then(res=>{if(res.ok){c.put(r,res.clone());recortar()}return res}))));
  }
  return; /* todo lo demás de Supabase va directo a la red */
 }
 if(u.hostname==='cdn.jsdelivr.net'){ /* librería supabase-js con versión fija: caché primero */
  e.respondWith(caches.open(C).then(c=>c.match(r).then(h=>h||fetch(r).then(res=>{if(res.ok)c.put(r,res.clone());return res}))));return}
 if(u.origin!==location.origin)return;
 e.respondWith(fetch(r).then(res=>{const cp=res.clone();caches.open(C).then(c=>c.put(r,cp)).catch(()=>{});return res}).catch(()=>caches.match(r)))});
self.addEventListener('push',e=>{const d=e.data?e.data.json():{title:'Nuevo mensaje',body:''};e.waitUntil(self.registration.showNotification(d.title,{body:d.body,icon:'icon.png',vibrate:[80,40,80]}))});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil(clients.openWindow('./panel/'))});
