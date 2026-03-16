# Frontend → Backend Reference Map

Quick-navigation guide linking frontend pages/views to their relevant SQL definitions.
Format: `[file:line](path#Lline)` — clickable in VSCode.

---

## Catalogs & Lookups (shared across pages)

These appear as dropdowns, selects, or reference data throughout the app.

| Catalog | Table | Enums |
|---------|-------|-------|
| Colores | [04:8](migration/04_alter_legacy_tables.sql#L8) `color` | — |
| Artículos | [04:64](migration/04_alter_legacy_tables.sql#L64) `articulo`, [04:81](migration/04_alter_legacy_tables.sql#L81) `articulo_tipo` | — |
| Unidades | [05:8](migration/05_new_tables_foundation.sql#L8) `unidad`, [05:34](migration/05_new_tables_foundation.sql#L34) `unidad_conversion` | — |
| Tipos de Item | [05:51](migration/05_new_tables_foundation.sql#L51) `item_tipo` | — |
| Tipos de Insumo | [05:71](migration/05_new_tables_foundation.sql#L71) `insumo_tipo`, [05:93](migration/05_new_tables_foundation.sql#L93) `colorante_tipo` | — |
| Almacenes / Ubicaciones | [05:240](migration/05_new_tables_foundation.sql#L240) `almacen`, [05:257](migration/05_new_tables_foundation.sql#L257) `ubicacion` | — |
| Tipos de Movimiento | [05:188](migration/05_new_tables_foundation.sql#L188) `item_movimiento_tipo` | [02:16](migration/02_enums.sql#L16) `item_movimiento_tipo_categoria_enum` |
| Tipos de Guía | [07:55](migration/07_new_tables_mes_doc_calidad.sql#L55) `guia_remision_tipo` | — |
| Operaciones MES | [07:138](migration/07_new_tables_mes_doc_calidad.sql#L138) `mes.operacion` | — |
| Operaciones Receta | [06:40](migration/06_receta_tables.sql#L40) `receta.operacion` | — |
| Tipos de Máquina | [07:168](migration/07_new_tables_mes_doc_calidad.sql#L168) `mes.maquina_tipo` | — |
| Tipos de Defecto | [07:396](migration/07_new_tables_mes_doc_calidad.sql#L396) `calidad.tipo_defecto` | [02:8](migration/02_enums.sql#L8) `calidad_estado_enum` |
| Estados (legacy) | [04:42](migration/04_alter_legacy_tables.sql#L42) `estado` | — |

---

## Page: Clientes / Proveedores / Terceros

**Route:** `/terceros`, `/clientes`, `/proveedores`

### Tables
- [05:287](migration/05_new_tables_foundation.sql#L287) `tercero` — nombre, razon_social, ruc, flg_cliente, flg_proveedor, cliente_id (legacy FK)

### Views
- Used in: `vw_colores`, `vw_lotes_rollos_stock`, `vw_partidas_lista_comercial`, `vw_lotes_rollos_despachados`

### Auth
- [10:169](migration/10_auth.sql#L169) `comercial_ver` policy covers tercero reads

---

## Page: Items / Catálogo de Artículos

**Route:** `/items`, `/items/rollos`, `/items/insumos`

### Tables
- [05:114](migration/05_new_tables_foundation.sql#L114) `item` — header (codigo, nombre, item_tipo_id, unidad_id)
- [05:137](migration/05_new_tables_foundation.sql#L137) `item_insumo_detalle` — insumo-specific attributes (medida, insumo_tipo_id, colorante_tipo_id, factor_stock)
- [05:157](migration/05_new_tables_foundation.sql#L157) `item_rollo_detalle` — rollo-specific attributes (articulo_id, flg_tenido, flg_rib)

### Views
- [08:22](migration/08_views.sql#L22) `vw_items` — item + item_tipo + unidad (used everywhere as base join)
- [08:457](migration/08_views.sql#L457) `inventario.vw_stock_insumos` — insumos with stock levels, avg price, tipo
- [08:396](migration/08_views.sql#L396) `inventario.vw_stock_rollos` — rollos with partida/color context

### Code generation triggers
- [03:154](migration/03_base_functions.sql#L154) `fn_trg_gen_codigo_item_rollo()` — auto-generates rollo codigo
- [03:176](migration/03_base_functions.sql#L176) `fn_trg_gen_codigo_item_insumo()` — auto-generates insumo codigo

---

## Page: Colores (Color x Cliente)

**Route:** `/colores`, `/recetas/colores`

### Tables
- `color` + `color_x_cliente` — [04:8](migration/04_alter_legacy_tables.sql#L8) `color` (hex added here)
- [11:7](migration/11_data_migration.sql#L7) hex data migration (color seed)
- `estado_desarrollo_color` — [06:14](migration/06_receta_tables.sql#L14) development states

### Views
- [08:7](migration/08_views.sql#L7) `vw_colores` — color_x_cliente + color + cliente (used in partidas, recetas, lotes)

---

## Page: Partidas (Órdenes Comerciales)

**Route:** `/partidas`, `/partidas/:id`

### Tables
- [07:13](migration/07_new_tables_mes_doc_calidad.sql#L13) `doc.partida` — header (numero, tercero_id, tenido_id, color_x_cliente_id, malla, rendimiento, fecha_acordada, estado, estado_facturacion)
- [07:41](migration/07_new_tables_mes_doc_calidad.sql#L41) `doc.partida_detalle` — line items (item_id, cantidad, unidad_id) — UNIQUE(partida_id, item_id)

### Enums
- [02:48](migration/02_enums.sql#L48) `partida_estado_enum` — CREADA → CANCELADA
- [02:125](migration/02_enums.sql#L125) `partida_facturacion_enum` — pendiente, parcial, facturado

### Views
- [08:99](migration/08_views.sql#L99) `doc.vw_partidas_lista_comercial` — aggregated view with items, weights, estado
- [08:335](migration/08_views.sql#L335) `doc.partida_resumen_tenido` — grouped by articulo_tipo

### Auth
- [10:169](migration/10_auth.sql#L169) `comercial_ver` RLS policies

---

## Page: Guías de Remisión

**Route:** `/guias`, `/guias/:id`

### Tables
- [07:102](migration/07_new_tables_mes_doc_calidad.sql#L102) `doc.guia_remision` — header (tipo, tercero_id, serie, correlativo, fecha_emision, fecha_recepcion)
- [07:121](migration/07_new_tables_mes_doc_calidad.sql#L121) `doc.guia_remision_detalle` — lines (item_id, lote_id, ubicacion_id, cantidad)
- [07:55](migration/07_new_tables_mes_doc_calidad.sql#L55) `doc.guia_remision_tipo` — type catalog (flg_emitida, flg_cliente, item_movimiento_tipo_id)

### Views
- [08:269](migration/08_views.sql#L269) `inventario.vw_item_proveedor_guia` — inbound guias with item + tercero
- [08:286](migration/08_views.sql#L286) `inventario.vw_lotes_rollos_despachados` — outbound rollos via guias

### Notes
- Lotes are **created at guia insertion time** for inbound guias
- `guia_remision_detalle.lote_id NOT NULL` (1 line per rollo)

---

## Page: Inventario / Stock General

**Route:** `/inventario`, `/inventario/stock`

### Tables
- [05:324](migration/05_new_tables_foundation.sql#L324) `inventario.lote` — physical lot/roll (item_id, documento_tipo, documento_id, cantidad kg, estado_calidad, propietario_id)
- [05:351](migration/05_new_tables_foundation.sql#L351) `inventario.item_movimientos` — single source of truth for all stock movements
- [05:371](migration/05_new_tables_foundation.sql#L371) `inventario.item_valoracion` — MAP + stock_qty cache (updated by trigger)
- [07:289](migration/07_new_tables_mes_doc_calidad.sql#L289) `inventario.pesaje` — weighing records (lote_id NOT NULL, peso_real)

### Views
- [08:39](migration/08_views.sql#L39) `inventario.vw_stock_actual` — aggregated movements → current stock per item/lote/ubicacion
- [08:381](migration/08_views.sql#L381) `inventario.vw_stock_general` — summary per item from vw_stock_actual
- [08:488](migration/08_views.sql#L488) `inventario.vw_lotes_disponibles` — lotes with positive stock
- [08:594](migration/08_views.sql#L594) `inventario.vw_items_movimientos` — movement ledger with item + lote + ubicacion context

### Trigger (MAP update)
- [05:380](migration/05_new_tables_foundation.sql#L380) `fn_trg_actualizar_map()` — Moving Average Price, fires AFTER INSERT on item_movimientos
- [09:125](migration/09_constraints_audit.sql#L125) `inventario.trfn_generar_secuencia_lote()` — auto-generates lote.secuencia on INSERT

---

## Page: Rollos en Stock

**Route:** `/inventario/rollos`

### Tables
- [05:324](migration/05_new_tables_foundation.sql#L324) `inventario.lote` — each row = 1 physical roll
- [05:157](migration/05_new_tables_foundation.sql#L157) `item_rollo_detalle` — rollo attributes (articulo, flg_tenido, flg_rib)

### Views
- [08:56](migration/08_views.sql#L56) `inventario.vw_lotes_rollos_stock` — full roll context: item, ubicacion, almacen, articulo, color, propietario
- [08:396](migration/08_views.sql#L396) `inventario.vw_stock_rollos` — CTE grouping by partida + color for stock totals

---

## Page: Cuadre de Inventario

**Route:** `/inventario/cuadre`

### Tables
- [05:451](migration/05_new_tables_foundation.sql#L451) `inventario.cuadre` — header (fecha_cuadre, fecha_cierre, estado)
- [05:462](migration/05_new_tables_foundation.sql#L462) `inventario.cuadre_detalle` — lines (item_id, cantidad_sistema, precio_promedio_sistema, cantidad_contada)

### Enums
- [05:444](migration/05_new_tables_foundation.sql#L444) `inventario.cuadre_estado_enum` — borrador, preparado, ejecutado, cancelado

### Views
- [05:476](migration/05_new_tables_foundation.sql#L476) `inventario.vw_cuadre` — cuadre + detalle + item context

---

## Page: Recetas de Teñido

**Route:** `/recetas/tenido`, `/recetas/tenido/:id`

### Tables
- [06:75](migration/06_receta_tables.sql#L75) `receta.tenido` — header (color_x_cliente_id, articulo_tipo_id, fibra, estado_id, flg_produccion)
- [06:110](migration/06_receta_tables.sql#L110) `receta.tenido_paso` — steps (operacion_id, orden, ph, temperatura, tiempo_min)
- [06:123](migration/06_receta_tables.sql#L123) `receta.tenido_paso_insumo` — step chemicals (item_id, cantidad, orden)
- [06:40](migration/06_receta_tables.sql#L40) `receta.operacion` — micro-level chemistry operations catalog

### Trigger
- [06:92](migration/06_receta_tables.sql#L92) `fn_trg_receta_tenido_flg_produccion()` — auto-sets flg_produccion on approval

### Notes
- `generar_receta` output: nested `pasos[].insumos[]` — flatten for consumption form
- `uq_receta_tenido_aprobada` unique index ensures one approved recipe per color_x_cliente + articulo_tipo

---

## Page: Recetas de Lavado de Máquina

**Route:** `/recetas/lavado`, `/recetas/lavado/:id`

### Tables
- [06:134](migration/06_receta_tables.sql#L134) `receta.lavado_maquina` — header (tipo_lavado_mq_id, valor_origen_id, valor_destino_id, flg_activo)
- [06:172](migration/06_receta_tables.sql#L172) `receta.lavado_maquina_paso` — steps (operacion_id, orden, ph, temperatura, tiempo_min)
- [06:185](migration/06_receta_tables.sql#L185) `receta.lavado_maquina_paso_insumo` — step chemicals (item_id, cantidad)

### Trigger
- [06:152](migration/06_receta_tables.sql#L152) `receta.fn_trg_lavado_maquina_immutable()` — prevents edits once used in production

---

## Page: Máquinas

**Route:** `/produccion/maquinas`, `/catalogo/maquinas`

### Tables
- [07:168](migration/07_new_tables_mes_doc_calidad.sql#L168) `mes.maquina_tipo` — type catalog
- [07:186](migration/07_new_tables_mes_doc_calidad.sql#L186) `mes.maquina` — (codigo, nombre, estado_actual, capacidad_min_kg, capacidad_max_kg, relacion_bano)

### Enums
- [02:79](migration/02_enums.sql#L79) `maquina_estado_enum` — activa, espera, configuracion, averia, mantenimiento

### Views
- [08:352](migration/08_views.sql#L352) `mes.vw_maquinas` — maquina + maquina_tipo

### Code generation
- [03:97](migration/03_base_functions.sql#L97) `mes.fn_trg_gen_codigo_maquina()` — auto-generates maquina.codigo

---

## Page: Órdenes de Producción

**Route:** `/produccion/ordenes`, `/produccion/ordenes/:id`

### Tables
- [07:273](migration/07_new_tables_mes_doc_calidad.sql#L273) `mes.orden_produccion` — header (partida_id, tipo, estado, fyh_inicio, fyh_fin)
- [07:300](migration/07_new_tables_mes_doc_calidad.sql#L300) `mes.orden_produccion_paso` — steps (operacion_id, maquina_asignada_id, receta_id, estado, relacion_bano, flg_genera_produccion)
- [07:324](migration/07_new_tables_mes_doc_calidad.sql#L324) `mes.orden_produccion_item` — materials assigned (item_id, lote_id, ubicacion_id)
- [07:338](migration/07_new_tables_mes_doc_calidad.sql#L338) `mes.orden_produccion_paso_item` — paso ↔ item join
- [07:249](migration/07_new_tables_mes_doc_calidad.sql#L249) `mes.ruta_plantilla` + `mes.ruta_plantilla_detalle` — production route templates
- [07:236](migration/07_new_tables_mes_doc_calidad.sql#L236) `mes.empleado_rol`, `mes.empleado`

### Enums
- [02:31](migration/02_enums.sql#L31) `orden_produccion_estado_enum` — CREADA → CANCELADA
- [02:65](migration/02_enums.sql#L65) `orden_produccion_tipo_enum` — NORMAL, REPROCESO, AJUSTE
- [02:73](migration/02_enums.sql#L73) `orden_produccion_paso_estado_enum` — PENDIENTE, EN_PROCESO, COMPLETADO, OMITIDO

### Views
- [08:157](migration/08_views.sql#L157) `mes.vw_ordenes_produccion` — full order with paso stats, materials, production stats (lateral subqueries)
- [08:566](migration/08_views.sql#L566) `mes.vw_pasos` — paso + orden + partida + operacion + maquina
- [08:365](migration/08_views.sql#L365) `mes.vw_partida_produccion_rollos` — output rollos per partida

### Auth
- [10:193](migration/10_auth.sql#L193) `produccion_ver` RLS policies

---

## Page: Programación / Scheduling Board

**Route:** `/produccion/programacion`

### Tables
- [07:350](migration/07_new_tables_mes_doc_calidad.sql#L350) `mes.programacion` — polymorphic (actividad_tipo + actividad_id, maquina_id, fecha, secuencia)
  - `actividad_tipo` values: `'ORDEN_PRODUCCION_PASO'`, `'LAVADO_MAQUINA'`

### Notes
- Board is machine-centric; two activity types are unified
- `get_actividades_sin_programar()` returns both types

---

## Page: Lavado de Máquina (Ejecución)

**Route:** `/produccion/lavado`

### Tables
- [07:368](migration/07_new_tables_mes_doc_calidad.sql#L368) `mes.lavado_maquina` — execution entity (receta_id, maquina_id, estado, empleado_id, fyh_inicio, fyh_fin)
- Chemical consumption → [05:351](migration/05_new_tables_foundation.sql#L351) `inventario.item_movimientos` with `documento_tipo='LAVADO_MAQUINA'`

### Functions
- `mes.iniciar_lavado()` and `mes.finalizar_lavado()` — defined in `funciones/mes.sql`

---

## Page: Calidad / Inspecciones

**Route:** `/calidad`, `/calidad/inspecciones`

### Tables
- [07:384](migration/07_new_tables_mes_doc_calidad.sql#L384) `calidad.inspeccion` — (lote_id, orden_produccion_paso_id, resultado, empleado_id, fyh_inspeccion)
- [07:428](migration/07_new_tables_mes_doc_calidad.sql#L428) `calidad.inspeccion_defecto` — defects found (tipo_defecto_id, cantidad)
- [07:436](migration/07_new_tables_mes_doc_calidad.sql#L436) `calidad.inspeccion_foto` — photos (ruta_archivo, etiqueta)
- [07:396](migration/07_new_tables_mes_doc_calidad.sql#L396) `calidad.tipo_defecto` — defect catalog (codigo, nombre, severidad)

### Enums
- [02:8](migration/02_enums.sql#L8) `calidad_estado_enum` — PENDIENTE, APROBADO, RECHAZADO, REPROCESO, CUARENTENA
  - Used in `inventario.lote.estado_calidad`

### Views
- [08:507](migration/08_views.sql#L507) `calidad.vw_lotes_pendientes_inspeccion` — lotes awaiting QC with full context
- [08:547](migration/08_views.sql#L547) `calidad.vw_inspecciones` — inspections + lote + item + empleado

### Auth
- [10:209](migration/10_auth.sql#L209) `calidad_ver` RLS policies

### Weighing gate
- [07:289](migration/07_new_tables_mes_doc_calidad.sql#L289) `inventario.pesaje` — `EXISTS(SELECT 1 FROM inventario.pesaje WHERE lote_id = ?)` gates production use

---

## Page: Compras

**Route:** `/compras`, `/compras/:id`

### Tables
- [07:471](migration/07_new_tables_mes_doc_calidad.sql#L471) `doc.compra` — purchase order (tercero_id, factura_proveedor_id, fecha)
- [07:483](migration/07_new_tables_mes_doc_calidad.sql#L483) `doc.compra_detalle` — lines (item_id, cantidad, precio_unitario)
- [07:492](migration/07_new_tables_mes_doc_calidad.sql#L492) `doc.compra_guia_remision` — compra ↔ guia link
- [07:447](migration/07_new_tables_mes_doc_calidad.sql#L447) `doc.factura_proveedor` — supplier invoice (serie, numero, tipo_pago, moneda, subtotal, igv, total, estado_pago)
- [07:498](migration/07_new_tables_mes_doc_calidad.sql#L498) `doc.letra` — payment letter (monto, fecha_giro, fecha_vencimiento, estado)

### Enums
- [02:92](migration/02_enums.sql#L92) `tipo_pago_enum` — al contado, credito
- [02:98](migration/02_enums.sql#L98) `estado_pago_enum` — pendiente, parcial, total, anulado
- [02:104](migration/02_enums.sql#L104) `letra_estado_enum` — emitida, pagada, vencida, protestada, anulada

### Views
- [08:228](migration/08_views.sql#L228) `doc.vw_compras` — compra + tercero + factura_proveedor with lateral subqueries

---

## Page: Facturación (Clientes)

**Route:** `/facturacion`, `/facturacion/:id`

### Tables
- [07:523](migration/07_new_tables_mes_doc_calidad.sql#L523) `doc.factura` — (tipo_comprobante, serie, numero, tercero_id, fecha_emision, moneda, subtotal, igv, total, estado, factura_origen_id)
- [07:559](migration/07_new_tables_mes_doc_calidad.sql#L559) `doc.factura_detalle` — lines (partida_id, descripcion, cantidad, unidad_id, precio_unitario, igv_porcentaje, subtotal/igv/total GENERATED)

### Enums
- [02:113](migration/02_enums.sql#L113) `factura_estado_enum` — borrador, emitida, anulada
- [02:125](migration/02_enums.sql#L125) `partida_facturacion_enum` — tracks billing progress on partida

### Trigger
- [09:61](migration/09_constraints_audit.sql#L61) `doc.fn_trg_factura_prevent_hard_delete()` — hard-delete protection

---

## Page: Usuarios / IAM

**Route:** `/admin/usuarios`

### Tables
- `usuario` (formerly `profiles`) — [04:173](migration/04_alter_legacy_tables.sql#L173) rename migration
- [10:17](migration/10_auth.sql#L17) `public.custom_access_token_hook()` — injects permissions into JWT
- [10:75](migration/10_auth.sql#L75) `public.jwt_has_permission()` — RLS helper used in policies

---

## Cross-cutting: Audit & Data Integrity

| Concern | Where |
|---------|-------|
| Audit fields (cre/mod/elm) | [03:39](migration/03_base_functions.sql#L39) triggers; [12](migration/12_triggers_audit.sql) applies to all tables |
| Audit log table | [09:81](migration/09_constraints_audit.sql#L81) `audit.data_audit` + [09:95](migration/09_constraints_audit.sql#L95) `audit.fn_audit_row()` |
| Canonical code generation | [03:10](migration/03_base_functions.sql#L10) `fn_trg_set_codigo_canon()` |
| Soft delete (flg_elm) | [03:59](migration/03_base_functions.sql#L59) `fn_trg_set_elm_fields()` |
| Hard-delete prevention | [03:88](migration/03_base_functions.sql#L88) `fn_trg_prevent_hard_delete()` — applied to partida, guia_remision, lote, orden_produccion |
| Immutable codigo | [03:76](migration/03_base_functions.sql#L76) `fn_trg_immutable_codigo()` — applied to catalog tables |
| Lote sequence | [09:125](migration/09_constraints_audit.sql#L125) `inventario.trfn_generar_secuencia_lote()` |
| Moving Average Price | [05:380](migration/05_new_tables_foundation.sql#L380) `fn_trg_actualizar_map()` |
| RLS policies | [10](migration/10_auth.sql) — all tables, grouped by role tier |
