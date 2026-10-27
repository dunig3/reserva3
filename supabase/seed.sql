-- Datos de demostración (negocios dulces y belleza). PIN del panel 0000, vendedores PIN 1234.
-- Las fotos ya están subidas (WebP comprimido) en el bucket va-imagenes bajo p/<negocio>/.
insert into va_negocios(slug, nombre, lema, emoji, hero, comision) values
 ('dulces',  'Dulces Mary',  'Postres caseros que enamoran', '🍰', 'p/dulces/hero-dulces.webp',   10),
 ('belleza', 'Belleza Luz',  'Tu brillo, a domicilio',       '💄', 'p/belleza/hero-belleza.webp', 15)
on conflict (slug) do nothing;

insert into va_negocio_priv(biz, pin_hash) values
 ('dulces',  extensions.crypt('0000', extensions.gen_salt('bf', 8))),
 ('belleza', extensions.crypt('0000', extensions.gen_salt('bf', 8)))
on conflict (biz) do nothing;

insert into va_productos(biz, n, d, p, img, orden)
select * from (values
 ('dulces',  'Torta de chocolate', 'Bizcocho húmedo con ganache',      15.00, 'p/dulces/torta.webp',     0),
 ('dulces',  'Quesillo',           'Receta tradicional con caramelo',  6.00, 'p/dulces/quesillo.webp',  1),
 ('dulces',  'Galletas x12',       'Con chispas de chocolate',          4.00, 'p/dulces/galletas.webp',  2),
 ('dulces',  'Cupcakes x6',        'Crema de chocolate batida',         7.00, 'p/dulces/cupcakes.webp',  3),
 ('belleza', 'Labial mate',        'Larga duración',                    5.00, 'p/belleza/labial.webp',   0),
 ('belleza', 'Crema facial',       'Hidratación 24 h',                  9.00, 'p/belleza/crema.webp',    1),
 ('belleza', 'Perfume 50 ml',      'Notas florales y ámbar',           18.00, 'p/belleza/perfume.webp',  2),
 ('belleza', 'Esmaltes x3',        'Rojo, dorado y vino',               6.00, 'p/belleza/esmaltes.webp', 3)
) v(biz, n, d, p, img, orden)
where not exists (select 1 from va_productos);

insert into va_vendedores(biz, cod, n, pin_hash) values
 ('dulces',  'ANA01',  'Ana',   extensions.crypt('1234', extensions.gen_salt('bf', 8))),
 ('dulces',  'LUIS02', 'Luis',  extensions.crypt('1234', extensions.gen_salt('bf', 8))),
 ('belleza', 'CARLA1', 'Carla', extensions.crypt('1234', extensions.gen_salt('bf', 8)))
on conflict do nothing;

insert into va_cuentas(biz, id, nombre, activo, campos, orden)
select b.slug, c.id, c.nombre, true, c.campos::jsonb, c.orden from va_negocios b cross join (values
 ('zelle',      'Zelle',      '{"Correo":"pagos@ejemplo.com","Titular":"Nombre del titular"}', 0),
 ('pago_movil', 'Pago Móvil', '{"Banco":"0102 Banco de Venezuela","Teléfono":"0414-0000000","Cédula":"V-00.000.000","Titular":"Nombre del titular"}', 1),
 ('binance',    'Binance',    '{"Pay ID":"000000000","Correo":"binance@ejemplo.com"}', 2),
 ('efectivo',   'Efectivo',   '{}', 3)
) c(id, nombre, campos, orden)
where b.slug in ('dulces', 'belleza')
on conflict do nothing;
