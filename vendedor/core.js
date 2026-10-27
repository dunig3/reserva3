/* Vendedor Automático — núcleo compartido (versión EN LÍNEA con Supabase)
   - Los datos viven en Supabase (proyecto dunig3, tablas va_*), ya no en localStorage.
   - La clave "anon" es pública por diseño: la seguridad la ponen RLS y las funciones RPC del servidor.
   - NUNCA pongas aquí la clave service_role. */
const VA_URL='https://xcaasrvlpyxfjeyqhyve.supabase.co';
const VA_ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhjYWFzcnZscHl4ZmpleXFoeXZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1MDg5OTYsImV4cCI6MjEwMTA4NDk5Nn0.27I4TF1oeZqVsBCcKpyrwF0EeWQ5EKQzcsTzO1T4qVM';
const VA_BUCKET='va-imagenes';
const BASE=(()=>{const s=document.currentScript.src;return s.slice(0,s.lastIndexOf('/')+1)})();
const sb=supabase.createClient(VA_URL,VA_ANON,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const QS=new URLSearchParams(location.search);
let BIZ=String(QS.get('n')||localStorage.getItem('va_biz')||'dulces').toLowerCase().replace(/[^a-z0-9-]/g,'').slice(0,30)||'dulces';
localStorage.setItem('va_biz',BIZ);
/* Espejo en memoria (misma forma que la demo, para cambiar poco las páginas) */
const DB={negocios:{},pedidos:[],mensajes:[],recibos:[],resumen:[]};
const RECIBO_MIN=30;
const N=()=>DB.negocios[BIZ];
const $=s=>document.querySelector(s);
const money=v=>'$'+Number(v).toFixed(2);
const hora=t=>new Date(t).toLocaleTimeString('es',{hour:'2-digit',minute:'2-digit'});
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
/* Rutas de imagen: 'p/...' o 'r/...' están en el bucket público; lo demás es relativo al sitio */
const img=p=>!p?BASE+'icon.png':/^(https?:|data:|blob:)/.test(p)?p:/^[pr]\//.test(p)?VA_URL+'/storage/v1/object/public/'+VA_BUCKET+'/'+p:BASE+p;

/* Llamada RPC: lanza Error con el mensaje en español que devuelve el servidor */
async function rpc(fn,args){
 let r;try{r=await sb.rpc(fn,args||{})}catch(e){throw new Error('Sin conexión. Revisa tu internet.')}
 if(r.error)throw new Error(r.error.message||'Error de conexión');
 if(r.data&&typeof r.data==='object'&&r.data.error)throw new Error(r.data.error);
 return r.data}
const esSesionVencida=e=>/Sesión vencida/i.test(e&&e.message||'');

/* ---------- Catálogo con caché local (se ve al instante, se revalida en segundo plano) ---------- */
const CAT_KEY='va_cat_v3',CAT_TTL=5*60*1000;
function _leerCache(){try{return JSON.parse(localStorage.getItem(CAT_KEY)||'null')}catch(e){return null}}
function _guardarCache(){try{localStorage.setItem(CAT_KEY,JSON.stringify({ts:Date.now(),negocios:DB.negocios}))}catch(e){}}
(function(){const c=_leerCache();if(c&&c.negocios)Object.assign(DB.negocios,c.negocios)})();
function catalogoFresco(){const c=_leerCache();return !!(c&&N()&&N().productos&&Date.now()-c.ts<CAT_TTL)}
async function cargarCatalogo(forzar){
 if(!forzar&&catalogoFresco())return false;
 const [n,p,c]=await Promise.all([
  sb.from('va_negocios').select('slug,nombre,lema,emoji,hero,comision,auto_resp').order('creado'),
  sb.from('va_productos').select('id,n,d,p,img').eq('biz',BIZ).order('orden').order('id'),
  sb.from('va_cuentas').select('id,nombre,activo,campos').eq('biz',BIZ).order('orden')]);
 if(n.error||p.error||c.error)throw new Error('No se pudo cargar la tienda. Revisa tu conexión.');
 const prev=DB.negocios;DB.negocios={};
 n.data.forEach(x=>{DB.negocios[x.slug]=Object.assign({vendedores:[]},prev[x.slug]||{},x,{pagos:[]})});
 if(!DB.negocios[BIZ]){BIZ=n.data[0]?n.data[0].slug:'dulces';localStorage.setItem('va_biz',BIZ);return cargarCatalogo(true)}
 Object.assign(N(),{productos:p.data.map(x=>({...x,id:String(x.id),p:Number(x.p)})),cuentas:c.data,autoOff:!N().auto_resp});
 _guardarCache();return true}
function actualizarCache(){_guardarCache()}

/* ---------- Sonido y notificaciones (igual que la demo) ---------- */
let actx;document.addEventListener('pointerdown',()=>{try{actx=actx||new (window.AudioContext||window.webkitAudioContext)();actx.resume()}catch(e){}});
function ding(){try{actx=actx||new (window.AudioContext||window.webkitAudioContext)();
 [880,1320].forEach((f,i)=>{const o=actx.createOscillator(),g=actx.createGain();o.type='sine';o.frequency.value=f;o.connect(g);g.connect(actx.destination);
 const t=actx.currentTime+i*.15;g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(.35,t+.02);g.gain.exponentialRampToValueAtTime(.0001,t+.35);o.start(t);o.stop(t+.4)});
 navigator.vibrate&&navigator.vibrate([80,40,80])}catch(e){}}
function toast(t){let e=$('#toast');if(!e){e=document.createElement('div');e.id='toast';e.className='toast';document.body.appendChild(e)}
 e.textContent=t;e.classList.add('show');clearTimeout(e._t);e._t=setTimeout(()=>e.classList.remove('show'),3200)}
function notify(title,body){ding();toast(title+': '+body);
 if('Notification' in window&&Notification.permission==='granted'&&document.hidden){
  (navigator.serviceWorker?navigator.serviceWorker.ready:Promise.reject()).then(r=>r.showNotification(title,{body,icon:BASE+'icon.png'})).catch(()=>{try{new Notification(title,{body})}catch(e){}})}}

/* ---------- Tiempo real ----------
   El servidor emite un "aviso" (Broadcast, sin datos personales) en el canal va:b:<negocio> o va:c:<cliente>
   cuando hay pedidos/mensajes nuevos. Al recibirlo, la página pide SOLO los cambios por RPC.
   Respaldo: sondeo ligero (20 s sin conexión en tiempo real; 2 min con conexión) y al volver a la pestaña. */
let onNuevo=()=>{},onRender=()=>{};
function escuchar(topic,sync){
 let vivo=false,ult=Date.now(),t=null;
 const run=()=>{clearTimeout(t);t=setTimeout(()=>{ult=Date.now();Promise.resolve(sync()).catch(e=>console.warn(e))},250)};
 const ch=sb.channel(topic,{config:{broadcast:{self:false}}}).on('broadcast',{event:'va'},run)
  .subscribe(s=>{const antes=vivo;vivo=s==='SUBSCRIBED';if(vivo&&!antes)run()});
 setInterval(()=>{if(document.hidden)return;if(!vivo||Date.now()-ult>120000)run()},20000);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)run()});
 addEventListener('online',run);
 return {canal:ch,ahora:run,cerrar:()=>sb.removeChannel(ch)}}
function markSeen(){} /* compatibilidad con la demo */

/* ---------- Imágenes: compresión en el navegador antes de subir ----------
   Canvas -> WebP (o JPEG si el navegador no soporta WebP). Al redibujar se eliminan los metadatos (EXIF/GPS). */
function _cargarImagen(file){return new Promise((ok,mal)=>{const u=URL.createObjectURL(file),im=new Image();
 im.onload=()=>{URL.revokeObjectURL(u);ok(im)};im.onerror=()=>{URL.revokeObjectURL(u);mal(new Error('Esa imagen no se pudo leer'))};im.src=u})}
const _blob=(c,tipo,q)=>new Promise(ok=>c.toBlob(ok,tipo,q));
async function comprimirImagen(file,{max=800,q=0.7,kb=80}={}){
 if(!file||!/^image\//.test(file.type))throw new Error('Elige una foto');
 let fuente;try{fuente=await createImageBitmap(file,{imageOrientation:'from-image'})}catch(e){fuente=await _cargarImagen(file)}
 let w=fuente.width,h=fuente.height,esc0=Math.min(1,max/Math.max(w,h));w=Math.round(w*esc0);h=Math.round(h*esc0);
 const c=document.createElement('canvas');let b=null,calidad=q;
 for(let i=0;i<8;i++){
  c.width=w;c.height=h;const x=c.getContext('2d');x.fillStyle='#fff';x.fillRect(0,0,w,h);x.drawImage(fuente,0,0,w,h);
  b=await _blob(c,'image/webp',calidad);
  if(!b||b.type!=='image/webp')b=await _blob(c,'image/jpeg',calidad);   /* Safari antiguo */
  if(b.size<=kb*1024)break;
  if(calidad>0.45)calidad-=0.1;else{w=Math.round(w*0.85);h=Math.round(h*0.85)}
 }
 if(b.size>195*1024)throw new Error('La foto sigue muy pesada; prueba con otra');
 return b}
/* Sube con un "ticket" de un solo uso que da el servidor (la política de Storage lo exige) */
async function subirImagen(blob,ticket){
 const ext=blob.type==='image/webp'?'webp':'jpg',path=ticket+'.'+ext;
 const {error}=await sb.storage.from(VA_BUCKET).upload(path,blob,{cacheControl:'31536000',contentType:blob.type,upsert:false});
 if(error)throw new Error('No se pudo subir la foto: '+error.message);
 return path}

if('serviceWorker' in navigator)navigator.serviceWorker.register(BASE+'sw.js',{scope:BASE}).catch(()=>{});
