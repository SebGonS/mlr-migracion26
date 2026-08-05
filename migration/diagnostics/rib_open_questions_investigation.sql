-- ═══════════════════════════════════════════════════════════════
-- Investigation: the 5 open rib questions from GRUPO_ARTICULO_HANDOFF.md
--
-- None of these can be answered by assertion — that is exactly the pattern
-- this migration exists to eliminate (operators forging workarounds instead
-- of the data reflecting physical reality). What follows is READ-ONLY
-- evidence-gathering: each query narrows the question using what the plant
-- has already told the system (approved recipe chemistry, actual usage), not
-- a guess. Recipe chemistry is CORRELATIONAL evidence, not proof — a fabric's
-- true fiber content is a physical fact the lab confirms, not something a
-- query can certify. Where a query can only narrow, not settle, it says so.
--
-- Chemistry background used below:
--   RX  (reactivo) / DIR (directo) → cellulosic fibers (cotton). Both are
--       "cellulosic-class" dyes — MLR's fibra=1 fabrics use one or both.
--   DISP (disperso)                → synthetic fibers (polyester). fibra=2
--       fabrics need DISP alongside RX/DIR to cover the poly component.
--   Elastane/Lycra is near-always <5-8% of a blend and is typically dyed
--   incidentally by whatever class covers the OTHER fiber(s) — it does not
--   usually justify its own dye class or push fibra up on its own. So if a
--   grupo's approved recipe uses ONLY RX/DIR, that is evidence its true
--   composition is cellulosic + elastane (fibra=1), regardless of what the
--   fibra column currently says.
-- ═══════════════════════════════════════════════════════════════

-- ── Q1: How many REAL rib fabrics exist? ──────────────────────
-- 33 forged rib items exist because flg_rib was bolted onto the BODY
-- fabric's articulo instead of rib being its own fabric. This query groups
-- every rib item by its body's fibra + grupo, as a first-pass count of how
-- many genuinely distinct rib constructions are in use (same fibra + same
-- dyeing chemistry = plausibly the same real fabric; different fibra =
-- definitely different fabrics).
-- ⚠ THIS QUERY NARROWS, IT DOES NOT SETTLE Q1 — two rib items with the same
-- fibra could still be physically different yarn counts/constructions that
-- only the plant can tell apart. Use it as a shortlist to confirm, not a count.
SELECT
    ar.fibra,
    COUNT(DISTINCT ar.id)                              AS articulos_forjados,
    COUNT(DISTINCT i.id)                                AS items,
    SUM((SELECT COUNT(*) FROM item_rollo_detalle ird2
         JOIN inventario.lote l2 ON l2.item_id = ird2.item_id
         WHERE ird2.item_id = i.id))                    AS rollos_aprox,
    string_agg(DISTINCT ar.nombre, ' | ' ORDER BY ar.nombre) AS nombres
FROM item_rollo_detalle ird
JOIN articulo ar ON ar.id = ird.articulo_id
JOIN item i       ON i.id = ird.item_id
WHERE ird.flg_rib = true
GROUP BY ar.fibra
ORDER BY ar.fibra;

-- ── Q2: Full Lycra Melange — cotton melange or cotton/poly melange? ──
-- Empirical proxy: what dye classes does its APPROVED recipe actually use?
-- Only RX/DIR present  → supports fibra=1 (cellulosic melange, current value correct)
-- DISP also present    → supports fibra=2 (poly component present, current value wrong)
-- No approved recipe   → no evidence available from data; must ask the lab directly
SELECT
    a.id, a.nombre, a.fibra AS fibra_actual,
    array_agg(DISTINCT ct.codigo) AS clases_colorante_usadas,
    COUNT(DISTINCT rt.id)         AS recetas_aprobadas
FROM articulo a
JOIN grupo_articulo_miembro gm ON gm.articulo_id = a.id
JOIN receta.tenido rt          ON rt.grupo_articulo_id = gm.grupo_articulo_id
                                AND rt.flg_produccion = true
JOIN receta.tenido_paso tp     ON tp.receta_id = rt.id
JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
JOIN item_insumo_detalle iid   ON iid.item_id = tpi.item_id
LEFT JOIN colorante_tipo ct    ON ct.id = iid.colorante_tipo_id
WHERE a.nombre ILIKE '%melange%' AND a.nombre ILIKE '%lycra%'
GROUP BY a.id, a.nombre, a.fibra;

-- ── Q3: Rib Lycrado (fibra=2) vs J Lycra / Full Lycra (fibra=1) ──
-- Same proxy as Q2, run across all three for direct comparison. If Rib
-- Lycrado's recipes use ONLY RX/DIR just like the other two, that is real
-- evidence the fibra=2 is a data error, not a true composition difference —
-- elastane alone does not justify DISP. If DISP genuinely appears only for
-- Rib Lycrado, that supports it legitimately containing polyester the others
-- don't (e.g. a poly-reinforced rib construction).
SELECT
    a.nombre, a.fibra AS fibra_actual,
    array_agg(DISTINCT ct.codigo) AS clases_colorante_usadas,
    COUNT(DISTINCT rt.id)         AS recetas_aprobadas
FROM articulo a
JOIN grupo_articulo_miembro gm ON gm.articulo_id = a.id
LEFT JOIN receta.tenido rt          ON rt.grupo_articulo_id = gm.grupo_articulo_id
                                    AND rt.flg_produccion = true
LEFT JOIN receta.tenido_paso tp     ON tp.receta_id = rt.id
LEFT JOIN receta.tenido_paso_insumo tpi ON tpi.paso_id = tp.id
LEFT JOIN item_insumo_detalle iid   ON iid.item_id = tpi.item_id
LEFT JOIN colorante_tipo ct         ON ct.id = iid.colorante_tipo_id
WHERE a.nombre IN ('Rib Lycrado', 'J Lycra', 'Full Lycra')
GROUP BY a.nombre, a.fibra;

-- ── Q4: 'Paquete de Cuellos' (306) vs 'Paquete Cuellos J 20/1' (324) ──
-- Duplicate-detection proxy, same shape as the Jersey/Gamuza dead-grupo check
-- (GRUPO_ARTICULO_HANDOFF.md decision 10): compare usage. If one is a live
-- orphan (0 rolls, 0 partidas) while the other carries real volume, that's
-- the same signature as the confirmed-dead Jersey/Gamuza case — strong
-- evidence of a legacy duplicate, not two real products.
SELECT
    a.id, a.nombre, a.fibra,
    (SELECT COUNT(*) FROM item_rollo_detalle ird
     JOIN item i2 ON i2.id = ird.item_id
     WHERE ird.articulo_id = a.id)                          AS rollos_totales,
    (SELECT COUNT(DISTINCT p.id) FROM mes.partida p
     JOIN grupo_articulo_miembro gm2 ON gm2.grupo_articulo_id = p.grupo_articulo_id
     WHERE gm2.articulo_id = a.id)                           AS partidas_totales
FROM articulo a
WHERE a.id IN (306, 324);

-- ── Q5: 'Rollo Rib Rib Lycrado' (298) — naming artifact or real trim item? ──
-- Two possibilities: (a) data-entry duplication (the repeated "Rib" is a
-- typo), or (b) a legitimate rib-trim-cut-from-rib-fabric item (cuffs/collars
-- are commonly cut from rib fabric regardless of body). Usage + membership
-- pattern helps distinguish: an active item with real rollos/partidas and a
-- distinct grupo membership is more likely (b); an orphan with the same
-- membership as plain 'Rib Lycrado' is more likely (a).
-- CORRECTED: "Rollo Rib Rib Lycrado" is an ITEM name (items are named
-- "Rollo " + articulo.nombre), not an articulo — the original query searched
-- the wrong table. This looks up the actual item and its underlying articulo.
SELECT
    i.id AS item_id, i.nombre AS item_nombre,
    ird2.flg_rib,
    a.id AS articulo_id, a.nombre AS articulo_nombre, a.fibra,
    (SELECT COUNT(*) FROM item_rollo_detalle ird WHERE ird.item_id = i.id) AS rollos_totales
FROM item i
LEFT JOIN item_rollo_detalle ird2 ON ird2.item_id = i.id
LEFT JOIN articulo a ON a.id = ird2.articulo_id
WHERE i.nombre ILIKE '%rib rib%'
   OR i.nombre ILIKE '%rollo rib rib%';

-- ── Q1 REVISED — full census: genuine rib fabric vs. clone/placeholder ──
-- Confirmed 2026-07-19: item names ALWAYS say "Rib X" (every rib-tracking
-- item is labeled that way), so item naming is not the signal. The real
-- distinction is whether the ARTICULO was ever dyed under its OWN identity —
-- genuine rib fabrics (e.g. Rib Lycrado) have real recetas/partidas run
-- against their own grupo; clones/placeholders were only ever created to
-- carry flg_rib on a roll and were dyed as a byproduct of the BODY's process,
-- so they show zero production of their own.
--
-- recetas_propias > 0 or partidas_propias > 0 → genuine, keep as its own fabric
-- both zero, fibra/name mirrors an existing body articulo → clone, collapse
--   onto the body's grupo when rib becomes an attribute instead of a fabric
SELECT
    a.id, a.nombre, a.fibra,
    g.id                                                             AS grupo_id,
    (SELECT COUNT(*) FROM grupo_articulo_miembro gm2
     WHERE gm2.grupo_articulo_id = g.id)                             AS n_miembros_grupo,
    (SELECT COUNT(*) FROM receta.tenido rt
     WHERE rt.grupo_articulo_id = g.id AND rt.flg_produccion = true) AS recetas_propias,
    (SELECT COUNT(*) FROM mes.partida p
     WHERE p.grupo_articulo_id = g.id AND p.fyh_elm IS NULL)         AS partidas_propias,
    (SELECT COUNT(*) FROM item_rollo_detalle ird
     WHERE ird.articulo_id = a.id)                                   AS rollos_totales
FROM articulo a
LEFT JOIN grupo_articulo_miembro gm ON gm.articulo_id = a.id
LEFT JOIN grupo_articulo g          ON g.id = gm.grupo_articulo_id
WHERE a.nombre ILIKE '%rib%'
ORDER BY recetas_propias DESC NULLS LAST, partidas_propias DESC NULLS LAST, a.nombre;

-- ═══════════════════════════════════════════════════════════════
-- WHAT NONE OF THIS CAN ANSWER — genuinely needs the plant/lab:
--   - Confirming a fiber composition the data hints at (recipes are what got
--     APPROVED, not a lab certificate of yarn content)
--   - Whether two same-fibra rib items are truly the same physical
--     construction (yarn count, gauge) or coincidentally share fibra
--   - Business intent behind a near-duplicate name (was 306 meant to be
--     retired when 324 was created, or do they serve different orders?)
-- ═══════════════════════════════════════════════════════════════
