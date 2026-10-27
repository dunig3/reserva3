/* Catálogo por talla · definición de la app.
   Los datos de abajo (seed) son SOLO de ejemplo: se usan en "Modo demo" y en el botón
   "Cargar catálogo de ejemplo" del panel. Tus datos reales viven en tu base de datos. */
(function () {
  const T = n => "d0000000-0000-4000-8000-00000000000" + n, C = n => "c1000000-0000-4000-8000-00000000000" + n, I = n => "a1000000-0000-4000-8000-0000000000" + String(n).padStart(2, "0");
  const ROPA = ["S", "M", "L", "XL"], ZAP = ["36", "37", "38", "39", "40", "41"];
  const p = (n, cat, nombre, precio, tallas, foto, fecha, nuevo, stock) => ({ id: I(n), categoria_id: C(cat), nombre, descripcion: "", precio, tallas: tallas.map(t => ({ t, stock: stock && stock[t] != null ? stock[t] : null })), fotos: ["img/" + foto + ".webp"], nuevo: !!nuevo, activo: true, orden: n, creado: fecha + "T12:00:00.000Z" });
  window.APP = {
    id: "catalogo-tallas", prefix: "cat", bucket: "cat-imagenes", titulo: "Catálogo por talla", icono: "👗", ownerRpc: "cat_reclamar", seedVersion: 2,
    seed: {
      cat_ajustes: [{ id: 1, datos: { nombre: "Moda Sierra", lema: "Ropa y calzado · Envíos a toda Venezuela", subtitulo: "Ropa · Calzado", insignia: "Temporada 2026", whatsapp: "584140000000", moneda: "$", banner: "img/1490481651871.webp", logo: "", envios: "🚚 Envíos a toda Venezuela · Pago móvil, Zelle o efectivo" } }],
      cat_tallas: [{ id: T(1), nombre: "Ropa", tallas: ROPA, orden: 1 }, { id: T(2), nombre: "Calzado", tallas: ZAP, orden: 2 }],
      cat_categorias: [
        { id: C(1), nombre: "Camisas", tallas_id: T(1), orden: 1 }, { id: C(2), nombre: "Vestidos", tallas_id: T(1), orden: 2 }, { id: C(3), nombre: "Jeans", tallas_id: T(1), orden: 3 },
        { id: C(4), nombre: "Zapatos", tallas_id: T(2), orden: 4 }, { id: C(5), nombre: "Deportivos", tallas_id: T(2), orden: 5 }],
      cat_productos: [
        p(1, 1, "Camisa denim clásica", 18, ["S", "M", "L", "XL"], "1596755094514", "2026-10-20", true),
        p(2, 1, "Camisa formal celeste", 22, ["M", "L", "XL"], "1620012253295", "2026-09-28"),
        p(3, 1, "Franela estampada", 12, ["S", "M", "L"], "1576566588028", "2026-10-02"),
        p(4, 2, "Vestido rojo floral", 35, ["S", "M", "L"], "1572804013309", "2026-10-22", true, { L: 0 }),
        p(5, 2, "Vestido largo de gala", 45, ["S", "M"], "1595777457583", "2026-09-15"),
        p(6, 2, "Vestido blanco verano", 28, ["S", "M", "L", "XL"], "1515372039744", "2026-10-10"),
        p(7, 3, "Jean clásico azul", 25, ["S", "M", "L", "XL"], "1542272604", "2026-09-30"),
        p(8, 3, "Jean recto oscuro", 27, ["M", "L", "XL"], "1624378439575", "2026-10-18", true),
        p(9, 4, "Tacones estampados", 38, ["36", "37", "38", "39"], "1543163521", "2026-10-05"),
        p(10, 4, "Zapato casual vinotinto", 30, ["37", "38", "39", "40", "41"], "1525966222134", "2026-10-24", true),
        p(11, 5, "Deportivo Runner rojo", 55, ["38", "39", "40", "41"], "1542291026", "2026-10-25", true),
        p(12, 5, "Deportivo urbano camel", 60, ["39", "40", "41"], "1549298916", "2026-09-20"),
        p(13, 5, "Deportivo pastel", 50, ["36", "37", "38", "39"], "1595950653106", "2026-10-12"),
        p(14, 5, "Deportivo blanco clásico", 48, ["37", "38", "39", "40", "41"], "1460353581641", "2026-08-30")],
      cat_pedidos: []
    },
    beforeInsert: {
      cat_pedidos(row, read) {
        const ps = read("cat_productos"); let tot = 0;
        row.items = row.items.map(it => {
          const p = ps.find(x => x.id === it.id && x.activo); if (!p) throw new Error("Un producto del pedido ya no está disponible");
          const t = (p.tallas || []).find(x => x.t === it.talla); if (!t) throw new Error("La talla " + it.talla + " no está disponible");
          if (t.stock != null && t.stock <= 0) throw new Error("La talla " + it.talla + " está agotada");
          const q = Math.max(1, Math.min(20, it.cant | 0)); tot += p.precio * q; return { id: p.id, nombre: p.nombre, precio: p.precio, talla: it.talla, cant: q };
        });
        row.total = Math.round(tot * 100) / 100; row.estado = "nuevo";
      }
    }
  };
})();
