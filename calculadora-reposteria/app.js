/* Calculadora para reposteras · definición de la app.
   Los datos de abajo son SOLO de ejemplo: se usan en "Modo demo", cuando no has iniciado
   sesión, y en el botón "Cargar ingredientes de ejemplo". Tus datos reales viven en tu cuenta. */
(function () {
  const G = n => "f0000000-0000-4000-8000-00000000000" + n;
  const ing = (n, nombre, unidad, cantidad, precio) => ({ id: G(n), user_id: "demo-user", nombre, unidad, cantidad, precio });
  const ingredientes = [
    ing(1, "Harina de trigo", "g", 1000, 1.2), ing(2, "Azúcar", "g", 1000, 0.9), ing(3, "Huevos", "und", 30, 5.4),
    ing(4, "Mantequilla", "g", 500, 5), ing(5, "Cacao en polvo", "g", 250, 3), ing(6, "Leche", "ml", 1000, 1.1), ing(7, "Caja y base", "und", 1, 1.5)];
  const receta = {
    id: "f1000000-0000-4000-8000-000000000001", user_id: "demo-user", nombre: "Torta de chocolate", margen: 60, porciones: 12,
    items: [{ ing: G(1), nombre: "Harina de trigo", cant: 500 }, { ing: G(2), nombre: "Azúcar", cant: 400 }, { ing: G(3), nombre: "Huevos", cant: 6 },
      { ing: G(4), nombre: "Mantequilla", cant: 250 }, { ing: G(5), nombre: "Cacao en polvo", cant: 120 }, { ing: G(6), nombre: "Leche", cant: 250 },
      { ing: G(7), nombre: "Caja y base", cant: 1 }, { ing: null, nombre: "Gas y electricidad", costo: 0.8 }]
  };
  const ajustes = { negocio: "Dulce Cálculo", moneda: "$", redondeo: 0.05, margen: 60, porciones: 12, whatsapp: "" };
  window.APP = {
    id: "calculadora-reposteria", prefix: "rep", bucket: "", titulo: "Mi calculadora", icono: "🎂", ownerRpc: "", loginSub: "Entra a tu cuenta para guardar tus ingredientes, precios y recetas", seedVersion: 2,
    seed: { rep_ingredientes: ingredientes, rep_recetas: [receta], rep_ajustes: [{ id: 1, user_id: "demo-user", datos: ajustes }] },
    defaults: { ingredientes, receta, ajustes },
    /* Cálculos compartidos por la calculadora y el panel */
    calc: {
      unitario: g => g && Number(g.cantidad) > 0 ? Number(g.precio) / Number(g.cantidad) : 0,
      costoItem(it, ING) { const g = it.ing && ING.find(x => x.id === it.ing); return g ? (Number(it.cant) || 0) * this.unitario(g) : (Number(it.costo) || 0); },
      numeros(r, ING, redondeo) {
        const cost = (r.items || []).reduce((a, it) => a + this.costoItem(it, ING), 0);
        const raw = cost * (1 + (Number(r.margen) || 0) / 100), step = Number(redondeo) || 0.01, por = Math.max(1, Number(r.porciones) || 1);
        const per = Math.ceil((raw / por) / step - 1e-9) * step, total = per * por;
        return { cost, per, total, profit: total - cost, perCost: cost / por };
      }
    }
  };
})();
