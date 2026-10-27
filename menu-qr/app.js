/* Menú QR · definición de la app.
   Los datos de abajo (seed) son SOLO de ejemplo: se usan en "Modo demo" y en el botón
   "Cargar menú de ejemplo" del panel. Tus datos reales viven en tu base de datos. */
(function () {
  const C = n => "c0000000-0000-4000-8000-00000000000" + n, I = n => "a0000000-0000-4000-8000-0000000000" + String(n).padStart(2, "0");
  const prod = (n, cat, nombre, descripcion, precio, foto, etiqueta, orden) => ({ id: I(n), categoria_id: C(cat), nombre, descripcion, precio, foto: "img/" + foto + ".webp", etiqueta: etiqueta || "", disponible: true, orden: orden || n });
  window.APP = {
    id: "menu-qr", prefix: "mqr", bucket: "mqr-imagenes", titulo: "Menú QR", icono: "🍽️", ownerRpc: "mqr_reclamar", seedVersion: 2,
    seed: {
      mqr_ajustes: [{ id: 1, datos: { nombre: "Arepera El Buen Sabor", lema: "Sabor andino desde 1998", ciudad: "Mérida, Venezuela", horario: "Lun a Dom · 7:00 am – 10:00 pm", whatsapp: "584140000000", moneda: "$", prefijo: "BS", portada: "img/29465174.webp", logo: "", abierto: true, mesas: 12 } }],
      mqr_categorias: [
        { id: C(1), nombre: "Arepas", orden: 1, activo: true }, { id: C(2), nombre: "Empanadas", orden: 2, activo: true },
        { id: C(3), nombre: "Bebidas", orden: 3, activo: true }, { id: C(4), nombre: "Postres", orden: 4, activo: true }],
      mqr_productos: [
        prod(1, 1, "Reina pepiada", "Pollo mechado, aguacate y mayonesa casera", 4.5, "29496092", "Favorita"),
        prod(2, 1, "Pabellón", "Carne mechada, caraotas negras, tajadas y queso", 5.5, "29465173", "Especial"),
        prod(3, 1, "Dominó", "Caraotas negras con queso blanco rallado", 3.5, "29496090"),
        prod(4, 1, "Catira", "Pollo mechado con queso amarillo", 4, "29496095"),
        prod(5, 1, "Pelúa", "Carne mechada con queso amarillo rallado", 4.5, "29496088"),
        prod(6, 2, "Empanada de carne", "Masa de maíz crujiente, carne molida guisada", 2, "28902899"),
        prod(7, 2, "Empanada de queso", "Rellena de queso blanco que se derrite", 1.8, "12469922"),
        prod(8, 2, "Empanada de pollo", "Pollo guisado con ají dulce", 2, "23526715"),
        prod(9, 2, "Empanada pabellón", "Carne, caraotas, tajada y queso", 2.5, "37025258", "Nueva"),
        prod(10, 2, "Tequeños (6 und)", "Palitos de queso con salsa de la casa", 3, "8305406"),
        prod(11, 3, "Papelón con limón", "Bien frío, endulzado con papelón", 1.5, "1621263764928", "Clásico"),
        prod(12, 3, "Jugo de parchita", "Natural, hecho al momento", 2, "1523371054106"),
        prod(13, 3, "Café marrón", "Café andino con leche espumada", 1, "1509042239860"),
        prod(14, 4, "Quesillo", "Flan venezolano con caramelo", 2.5, "quesillo", "Casero"),
        prod(15, 4, "Torta de chocolate", "Húmeda, con ganache de cacao venezolano", 3, "torta"),
        prod(16, 4, "Marquesa de chocolate", "Capas de galleta, crema y chocolate", 3, "1571115177098")],
      mqr_pedidos: []
    },
    /* En modo demo imitamos lo que hace el servidor: precios reales y total recalculado */
    beforeInsert: {
      mqr_pedidos(row, read) {
        const ps = read("mqr_productos"); let tot = 0;
        row.items = row.items.map(it => { const p = ps.find(x => x.id === it.id && x.disponible); if (!p) throw new Error("Un producto del pedido ya no está disponible"); const q = Math.max(1, Math.min(50, it.cant | 0)); tot += p.precio * q; return { id: p.id, nombre: p.nombre, precio: p.precio, cant: q }; });
        row.total = Math.round(tot * 100) / 100; row.estado = "nuevo";
      }
    }
  };
})();
