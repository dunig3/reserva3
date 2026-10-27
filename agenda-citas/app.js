/* Agenda de citas · definición de la app.
   Los datos de abajo (seed) son SOLO de ejemplo: se usan en "Modo demo" y en el botón
   "Cargar servicios de ejemplo" del panel. Tus datos reales viven en tu base de datos. */
(function () {
  const S = n => "b0000000-0000-4000-8000-00000000000" + n;
  const pad = n => String(n).padStart(2, "0");
  const dia = k => { const d = new Date(); d.setDate(d.getDate() + k); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); };
  const horario = {}; for (let i = 0; i < 7; i++) horario[i] = { abierto: i !== 0, desde: "09:00", hasta: i === 6 ? "14:00" : "17:00" };
  let ci = 0; const cita = (k, hora, s, cliente, estado) => ({ id: "e0000000-0000-4000-8000-0000000000" + pad(++ci), servicio_id: S(s), servicio: ["", "Corte clásico", "Corte + barba", "Degradado (fade)", "Afeitado"][s], precio: [0, 5, 8, 6, 4][s], duracion: [0, 30, 45, 40, 20][s], fecha: dia(k), hora, cliente, telefono: "0414 000 0000", nota: "", estado: estado || "confirmada" });
  window.APP = {
    id: "agenda-citas", prefix: "agc", bucket: "agc-imagenes", titulo: "Agenda de citas", icono: "✂️", ownerRpc: "agc_reclamar", seedVersion: 2,
    seed: {
      agc_ajustes: [{ id: 1, datos: { nombre: "Barbería Los Andes", direccion: "Av. 4 Bolívar, Mérida", whatsapp: "584140000000", moneda: "$", portada: "img/1585747860715.webp", logo: "", horario, intervalo: 45, dias: 10 } }],
      agc_servicios: [
        { id: S(1), nombre: "Corte clásico", precio: 5, duracion: 30, foto: "img/1622296089863.webp", etiqueta: "", activo: true, orden: 1 },
        { id: S(2), nombre: "Corte + barba", precio: 8, duracion: 45, foto: "img/1532710093739.webp", etiqueta: "Popular", activo: true, orden: 2 },
        { id: S(3), nombre: "Degradado (fade)", precio: 6, duracion: 40, foto: "img/1593702275687.webp", etiqueta: "", activo: true, orden: 3 },
        { id: S(4), nombre: "Afeitado", precio: 4, duracion: 20, foto: "img/1517832606299.webp", etiqueta: "", activo: true, orden: 4 }],
      agc_bloqueos: [],
      agc_citas: [cita(1, "09:45", 2, "Luis Rondón"), cita(1, "12:00", 1, "Pedro Uzcátegui", "pendiente"), cita(2, "10:30", 3, "José Pérez"), cita(2, "14:15", 4, "Carlos Díaz", "pendiente"), cita(3, "09:00", 1, "Andrés Molina")]
    },
    /* Una sola cita activa por fecha y hora (igual que el índice único del servidor) */
    unique: { agc_citas: r => r.estado !== "cancelada" ? r.fecha + "|" + r.hora : null },
    beforeInsert: {
      agc_citas(row, read) {
        if (read("agc_bloqueos").some(b => b.fecha === row.fecha)) throw new Error("Ese día no hay atención");
        const s = read("agc_servicios").find(x => x.id === row.servicio_id && x.activo); if (!s) throw new Error("Ese servicio ya no está disponible");
        Object.assign(row, { servicio: s.nombre, precio: s.precio, duracion: s.duracion, estado: "pendiente" });
      }
    },
    localRpc: {
      async agc_ocupados(db, a) { return (await db.select("agc_citas")).filter(c => c.estado !== "cancelada" && c.fecha >= a.p_desde && c.fecha <= a.p_hasta).map(c => ({ fecha: c.fecha, hora: c.hora })); }
    }
  };
})();
