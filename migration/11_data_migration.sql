-- MLR Database Migration Script
-- Migrates data from existing tables to new PostgreSQL schema
-- Execute after tablas.sql and funciones.sql are loaded

BEGIN;
UPDATE letra_compra
SET fyh_cre_tz = fyh_cre::timestamp + INTERVAL '5 hours'
WHERE fyh_cre!=fyh_cre_tz::timestamp;

-- Update colors with hex values
UPDATE color SET hex = '#0066CC' WHERE color = 'A. Brasil';
UPDATE color SET hex = '#002F5F' WHERE color = 'A. Marino';
UPDATE color SET hex = '#1A3A52' WHERE color = 'A. Marino Jas';
UPDATE color SET hex = '#6B8E23' WHERE color = 'Aceituna';
UPDATE color SET hex = '#708090' WHERE color = 'Acero';
UPDATE color SET hex = '#B0C4DE' WHERE color = 'Acero Claro';
UPDATE color SET hex = '#4F5A65' WHERE color = 'Acero Oscuro';
UPDATE color SET hex = '#8B7355' WHERE color = 'Antique';
UPDATE color SET hex = '#9B8565' WHERE color = 'Antique 001';
UPDATE color SET hex = '#A89575' WHERE color = 'Antique 002';
UPDATE color SET hex = '#00FFFF' WHERE color = 'Aqua';
UPDATE color SET hex = '#7FFFD4' WHERE color = 'Aqua Piero';
UPDATE color SET hex = '#F4E4C1' WHERE color = 'Arena';
UPDATE color SET hex = '#5F7F8F' WHERE color = 'Azul Acero';
UPDATE color SET hex = '#8FA9BA' WHERE color = 'Azul Acero Claro';
UPDATE color SET hex = '#000080' WHERE color = 'Azul Navy';
UPDATE color SET hex = '#191970' WHERE color = 'Azul Noche';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Azulino';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Azulino (Sky)';
UPDATE color SET hex = '#F5F5DC' WHERE color = 'Beige';
UPDATE color SET hex = '#EDE9E3' WHERE color = 'Beige Entero';
UPDATE color SET hex = '#D3C5B8' WHERE color = 'Beige Humo';
UPDATE color SET hex = '#1C1C1C' WHERE color = 'Black Camote';
UPDATE color SET hex = '#FFFFFF' WHERE color = 'Blanco';
UPDATE color SET hex = '#FFF8DC' WHERE color = 'Blanco Cremoso';
UPDATE color SET hex = '#FFB6C1' WHERE color = 'Blom';
UPDATE color SET hex = '#4682B4' WHERE color = 'Blue Cal';
UPDATE color SET hex = '#800020' WHERE color = 'Borgoña';
UPDATE color SET hex = '#6B1F3D' WHERE color = 'Borgoña Jas';
UPDATE color SET hex = '#FFC0CB' WHERE color = 'Bubble';
UPDATE color SET hex = '#4A7C59' WHERE color = 'Cactus';
UPDATE color SET hex = '#6F4E37' WHERE color = 'Café';
UPDATE color SET hex = '#C19A6B' WHERE color = 'Camello';
UPDATE color SET hex = '#997A5E' WHERE color = 'Capuchino';
UPDATE color SET hex = '#1AC1DD' WHERE color = 'Caribean';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Celeste';
UPDATE color SET hex = '#ADD8E6' WHERE color = 'Celeste BB';
UPDATE color SET hex = '#A68B6B' WHERE color = 'Camell Osc';
UPDATE color SET hex = '#6CA6CD' WHERE color = 'Celeste Int';
UPDATE color SET hex = '#5DADE2' WHERE color = 'Celeste Mego';
UPDATE color SET hex = '#A4C9E6' WHERE color = 'Celeste SM';
UPDATE color SET hex = '#808080' WHERE color = 'Cemento';
UPDATE color SET hex = '#A9A9A9' WHERE color = 'Cemento Claro';
UPDATE color SET hex = '#FDB462' WHERE color = 'Chicha';
UPDATE color SET hex = '#FF69B4' WHERE color = 'Chicle';
UPDATE color SET hex = '#FF1493' WHERE color = 'Chicle Neon';
UPDATE color SET hex = '#FF77FF' WHERE color = 'Chicle Piero';
UPDATE color SET hex = '#8B4513' WHERE color = 'Antique Bronze';
UPDATE color SET hex = '#7B3F00' WHERE color = 'Chocolate';
UPDATE color SET hex = '#0047AB' WHERE color = 'Cobalto';
UPDATE color SET hex = '#D2691E' WHERE color = 'Cocoa';
UPDATE color SET hex = '#722F37' WHERE color = 'Conchevino';
UPDATE color SET hex = '#FF7F50' WHERE color = 'Coral';
UPDATE color SET hex = '#FF8C69' WHERE color = 'Coral Piero';
UPDATE color SET hex = '#FFFDD0' WHERE color = 'Crema';
UPDATE color SET hex = '#F0F8FF' WHERE color = 'Cristal';
UPDATE color SET hex = '#1560BD' WHERE color = 'Denin';
UPDATE color SET hex = '#FF6347' WHERE color = 'Exhuberant';
UPDATE color SET hex = '#FF3855' WHERE color = 'Fresa';
UPDATE color SET hex = '#FF00FF' WHERE color = 'Fucsia';
UPDATE color SET hex = '#8B0000' WHERE color = 'Guinda';
UPDATE color SET hex = '#663399' WHERE color = 'Hendrix';
UPDATE color SET hex = '#FF6B6B' WHERE color = 'Hot Coral';
UPDATE color SET hex = '#0066CC' WHERE color = 'Italiano';
UPDATE color SET hex = '#8F7E4F' WHERE color = 'Kaki';
UPDATE color SET hex = '#C41E3A' WHERE color = 'Lacre';
UPDATE color SET hex = '#C8A2C8' WHERE color = 'Lila';
UPDATE color SET hex = '#E6E6FA' WHERE color = 'Lila Pastel';
UPDATE color SET hex = '#DA70D6' WHERE color = 'Lila Piero';
UPDATE color SET hex = '#2C3539' WHERE color = 'London Osc';
UPDATE color SET hex = '#FBEC5D' WHERE color = 'Maiz';
UPDATE color SET hex = '#FF8C00' WHERE color = 'Mandarina';
UPDATE color SET hex = '#800000' WHERE color = 'Marron';
UPDATE color SET hex = '#E5E5E5' WHERE color = 'Melange';
UPDATE color SET hex = '#F7F7F7' WHERE color = 'Melange 1%';
UPDATE color SET hex = '#ECECEC' WHERE color = 'Melange 10%';
UPDATE color SET hex = '#F3F3F3' WHERE color = 'Melange 2%';
UPDATE color SET hex = '#FDBCB4' WHERE color = 'Melon';
UPDATE color SET hex = '#98FF98' WHERE color = 'Menta';
UPDATE color SET hex = '#4A5F7A' WHERE color = 'Faded Denin';
UPDATE color SET hex = '#B0E0E6' WHERE color = 'Mentol';
UPDATE color SET hex = '#B8D4E8' WHERE color = 'Celeste Panda';
UPDATE color SET hex = '#FFDB58' WHERE color = 'Mostaza Entero';
UPDATE color SET hex = '#000080' WHERE color = 'Navy';
UPDATE color SET hex = '#FFA500' WHERE color = 'Naranja';
UPDATE color SET hex = '#000000' WHERE color = 'Negro';
UPDATE color SET hex = '#2C2C2C' WHERE color = 'Negro Grafito';
UPDATE color SET hex = '#1A1A1A' WHERE color = 'Negro Jas';
UPDATE color SET hex = '#E3BC9A' WHERE color = 'Nude';
UPDATE color SET hex = '#CC7722' WHERE color = 'Ocre';
UPDATE color SET hex = '#808000' WHERE color = 'Olive';
UPDATE color SET hex = '#E7C6A5' WHERE color = 'Palo Rosa';
UPDATE color SET hex = '#C8A882' WHERE color = 'Palo Rosa Oscuro';
UPDATE color SET hex = '#FFEFD5' WHERE color = 'Papaya';
UPDATE color SET hex = '#F5E6D3' WHERE color = 'Papiro';
UPDATE color SET hex = '#FFB6C1' WHERE color = 'Rosado Claro';
UPDATE color SET hex = '#EAE6CA' WHERE color = 'Perla';
UPDATE color SET hex = '#93C572' WHERE color = 'Pistacho';
UPDATE color SET hex = '#5B9BD5' WHERE color = 'Pitufo';
UPDATE color SET hex = '#4A5568' WHERE color = 'Plomo Colegial';
UPDATE color SET hex = '#708090' WHERE color = 'Plomo Pizarra';
UPDATE color SET hex = '#C0C0C0' WHERE color = 'Plomo Plata';
UPDATE color SET hex = '#8B8589' WHERE color = 'Rata';
UPDATE color SET hex = '#FF0000' WHERE color = 'Rojo';
UPDATE color SET hex = '#DC143C' WHERE color = 'Rojo Bandera';
UPDATE color SET hex = '#B22222' WHERE color = 'Rojo Deep';
UPDATE color SET hex = '#E63946' WHERE color = 'Rojo Piero';
UPDATE color SET hex = '#BC8F8F' WHERE color = 'Rosa Vieja';
UPDATE color SET hex = '#FFC0CB' WHERE color = 'Rosado';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Celeste Piero';
UPDATE color SET hex = '#E2725B' WHERE color = 'Terracota';
UPDATE color SET hex = '#5C4033' WHERE color = 'Topo';
UPDATE color SET hex = '#48D1CC' WHERE color = 'Turqueza BB';
UPDATE color SET hex = '#008080' WHERE color = 'Turqueza Osc';
UPDATE color SET hex = '#8F00FF' WHERE color = 'Uva Piero';
UPDATE color SET hex = '#7FFFD4' WHERE color = 'V. Agua';
UPDATE color SET hex = '#006A4E' WHERE color = 'V. Botella';
UPDATE color SET hex = '#0047AB' WHERE color = 'V. Cobalto';
UPDATE color SET hex = '#228B22' WHERE color = 'V. Hoja';
UPDATE color SET hex = '#00A86B' WHERE color = 'V. Jade';
UPDATE color SET hex = '#8DB600' WHERE color = 'V. Manzana';
UPDATE color SET hex = '#4B5320' WHERE color = 'V. Militar';
UPDATE color SET hex = '#50C878' WHERE color = 'V. Monina';
UPDATE color SET hex = '#6B8E23' WHERE color = 'V. Olivo';
UPDATE color SET hex = '#7FFF00' WHERE color = 'V. Perico';
UPDATE color SET hex = '#722F37' WHERE color = 'Vino';
UPDATE color SET hex = '#8B00FF' WHERE color = 'Viola';
UPDATE color SET hex = '#F4E87C' WHERE color = 'Yellow Mist';
UPDATE color SET hex = '#001F3F' WHERE color = 'A. Marino Oscuro';
UPDATE color SET hex = '#C41E3A' WHERE color = 'Rojo Navidad';
UPDATE color SET hex = '#3A4F5F' WHERE color = 'London (Escolar)';
UPDATE color SET hex = '#FFE5B4' WHERE color = 'ppt';
UPDATE color SET hex = '#003366' WHERE color = 'Nautica';
UPDATE color SET hex = '#E0115F' WHERE color = 'Ruby';
UPDATE color SET hex = '#A4C9E6' WHERE color = 'Celeste Voxu';
UPDATE color SET hex = '#FFB6D9' WHERE color = 'Rosado BB';
UPDATE color SET hex = '#7C5940' WHERE color = 'Tabaco';
UPDATE color SET hex = '#556B8C' WHERE color = 'Acero Navy';
UPDATE color SET hex = '#E8D5C4' WHERE color = 'Beige Piero';
UPDATE color SET hex = '#6A8CAF' WHERE color = 'Acero Boys';
UPDATE color SET hex = '#FF1DCE' WHERE color = 'Fucsia Intenso';
UPDATE color SET hex = '#FFD700' WHERE color = 'Amarillo Tp';
UPDATE color SET hex = '#8B008B' WHERE color = 'Morado';
UPDATE color SET hex = '#B0C4DE' WHERE color = 'Acero Pastel';
UPDATE color SET hex = '#614051' WHERE color = 'Ciruela';
UPDATE color SET hex = '#0000FF' WHERE color = 'Azul';
UPDATE color SET hex = '#D4B896' WHERE color = 'Beige Oscuro';
UPDATE color SET hex = '#FFD1A4' WHERE color = 'Melon BB';
UPDATE color SET hex = '#C19A6B' WHERE color = 'Camell';
UPDATE color SET hex = '#FF4444' WHERE color = 'Rojo G';
UPDATE color SET hex = '#6495ED' WHERE color = 'Dusty Blue';
UPDATE color SET hex = '#C4E4FF' WHERE color = 'Country Air';
UPDATE color SET hex = '#E6C3E6' WHERE color = 'Orchid Tint';
UPDATE color SET hex = '#FFD5E5' WHERE color = 'Cloud Pink';
UPDATE color SET hex = '#FFBFD3' WHERE color = 'Heavenly Pink';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Illucion Blue';
UPDATE color SET hex = '#40E0D0' WHERE color = 'Turqueza';
UPDATE color SET hex = '#01796F' WHERE color = 'V. Pino';
UPDATE color SET hex = '#FFB3D9' WHERE color = 'Chicle Claro';
UPDATE color SET hex = '#D4AF88' WHERE color = 'Camello Polo';
UPDATE color SET hex = '#004D40' WHERE color = 'V. Botella Osc';
UPDATE color SET hex = '#A4BCE6' WHERE color = 'Celeste Ciruelo';
UPDATE color SET hex = '#8FA99C' WHERE color = 'V. Cemento';
UPDATE color SET hex = '#B0E0E6' WHERE color = 'Celeste Claro';
UPDATE color SET hex = '#FF90B3' WHERE color = 'Chicle Fte';
UPDATE color SET hex = '#6F2DA8' WHERE color = 'Grapeade';
UPDATE color SET hex = '#FFB6D9' WHERE color = 'Misi';
UPDATE color SET hex = '#6B7C8C' WHERE color = 'Acero 03';
UPDATE color SET hex = '#4A90E2' WHERE color = 'Bahia';
UPDATE color SET hex = '#D4B896' WHERE color = 'Camello Claro';
UPDATE color SET hex = '#EFEFEF' WHERE color = 'Melange 3%';
UPDATE color SET hex = '#F0D5C4' WHERE color = 'Palo Rosa Claro';
UPDATE color SET hex = '#DDA0DD' WHERE color = 'Orchid Ami';
UPDATE color SET hex = '#E5C4B4' WHERE color = 'Palo Rosa Ami';
UPDATE color SET hex = '#9ACD32' WHERE color = 'Manzanilla';
UPDATE color SET hex = '#FADADD' WHERE color = 'Dawn Pink';
UPDATE color SET hex = '#FF69B4' WHERE color = 'Rosado Intenso';
UPDATE color SET hex = '#D8BFD8' WHERE color = 'Lila 2';
UPDATE color SET hex = '#36454F' WHERE color = 'Charcoal';
UPDATE color SET hex = '#E5E4E2' WHERE color = 'Chalk';
UPDATE color SET hex = '#F0E68C' WHERE color = 'Arena 1';
UPDATE color SET hex = '#556B2F' WHERE color = 'Olivo Osc';
UPDATE color SET hex = '#A0522D' WHERE color = 'Cocoa Osc';
UPDATE color SET hex = '#5F7F8F' WHERE color = 'A. Acero Jasp';
UPDATE color SET hex = '#4A5568' WHERE color = 'P.Colegial Jasp';
UPDATE color SET hex = '#3C4E5F' WHERE color = 'Acero Osc 2';
UPDATE color SET hex = '#9ACD32' WHERE color = 'Olivo Claro';
UPDATE color SET hex = '#FFC0CB' WHERE color = 'Rosado Pink';
UPDATE color SET hex = '#3A4F5F' WHERE color = 'Diesel';
UPDATE color SET hex = '#5F7F8F' WHERE color = 'Acero JMR';
UPDATE color SET hex = '#C08762' WHERE color = 'Cocoa 1002';
UPDATE color SET hex = '#D8BFE8' WHERE color = 'Lila BB';
UPDATE color SET hex = '#AFEEEE' WHERE color = 'V. Agua BB';
UPDATE color SET hex = '#A68B6B' WHERE color = 'Camello Osc';
UPDATE color SET hex = '#7C8C5C' WHERE color = 'V. Palta';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Sky';
UPDATE color SET hex = '#4682B4' WHERE color = 'Steel Blue';
UPDATE color SET hex = '#8B0000' WHERE color = 'Bordeen';
UPDATE color SET hex = '#9B8565' WHERE color = 'Antique Entero';
UPDATE color SET hex = '#4B0082' WHERE color = 'Indigo';
UPDATE color SET hex = '#5C0120' WHERE color = 'Guinda Oscuro';
UPDATE color SET hex = '#78184A' WHERE color = 'Pansy';
UPDATE color SET hex = '#F0E6D8' WHERE color = 'Beige 02';
UPDATE color SET hex = '#6A8CAF' WHERE color = 'Acero Blue';
UPDATE color SET hex = '#B0E0E6' WHERE color = 'V. Agua 2';
UPDATE color SET hex = '#CC99CC' WHERE color = 'Agatha';
UPDATE color SET hex = '#6F4E37' WHERE color = 'Habano';
UPDATE color SET hex = '#D2122E' WHERE color = 'rojo 19-1662 tcx';
UPDATE color SET hex = '#9CAF88' WHERE color = 'Sage Green';
UPDATE color SET hex = '#228B22' WHERE color = 'New Green';
UPDATE color SET hex = '#E6E6FA' WHERE color = 'Lavanda';
UPDATE color SET hex = '#E8D5B7' WHERE color = 'Soya';
UPDATE color SET hex = '#3A4F5F' WHERE color = 'London';
UPDATE color SET hex = '#EDE1D4' WHERE color = 'Tofi';
UPDATE color SET hex = '#A29587' WHERE color = 'P. Rata';
UPDATE color SET hex = '#FF007F' WHERE color = 'Rosa';
UPDATE color SET hex = '#A8E4A0' WHERE color = 'Menta SM';
UPDATE color SET hex = '#6B8C9C' WHERE color = 'Acero 01';
UPDATE color SET hex = '#708090' WHERE color = 'Acero 02';
UPDATE color SET hex = '#4A5F6F' WHERE color = 'Acero Deep';
UPDATE color SET hex = '#3C4E5F' WHERE color = 'Acero Osc';
UPDATE color SET hex = '#FFFF00' WHERE color = 'Amarillo';
UPDATE color SET hex = '#FFD700' WHERE color = 'Amarillo Amy';
UPDATE color SET hex = '#FFBF00' WHERE color = 'Amarillo Brasil';
UPDATE color SET hex = '#FFA500' WHERE color = 'Amarillo Brasil 02';
UPDATE color SET hex = '#FFDB58' WHERE color = 'Amarillo Bte';
UPDATE color SET hex = '#FFD700' WHERE color = 'Amarillo Oro';
UPDATE color SET hex = '#FDFD96' WHERE color = 'Amarillo Pato';
UPDATE color SET hex = '#FF69B4' WHERE color = 'Amy Fresa';
UPDATE color SET hex = '#8B4513' WHERE color = 'Apache';
UPDATE color SET hex = '#000080' WHERE color = 'Blue Navy';
UPDATE color SET hex = '#6B1F3D' WHERE color = 'Borgoña Osc';
UPDATE color SET hex = '#FF77FF' WHERE color = 'Bubble Gumer';
UPDATE color SET hex = '#00BFFF' WHERE color = 'Capri';
UPDATE color SET hex = '#C9A468' WHERE color = 'Carton';
UPDATE color SET hex = '#8FAABE' WHERE color = 'Celeste Acero';
UPDATE color SET hex = '#87CEEB' WHERE color = 'Celeste Sky';
UPDATE color SET hex = '#FF1493' WHERE color = 'Chicle Osc';
UPDATE color SET hex = '#5C3317' WHERE color = 'Chocolate Osc';
UPDATE color SET hex = '#FF8C82' WHERE color = 'Coralino';
UPDATE color SET hex = '#FFE4E1' WHERE color = 'Cristal Pink';
UPDATE color SET hex = '#1C1C1C' WHERE color = 'Dark';
UPDATE color SET hex = '#3A7D9A' WHERE color = 'Enfermera';
UPDATE color SET hex = '#FF00FF' WHERE color = 'Fucsia Virtual';
UPDATE color SET hex = '#555555' WHERE color = 'Gris Osc';
UPDATE color SET hex = '#F8F0E3' WHERE color = 'Hueso';
UPDATE color SET hex = '#4682B4' WHERE color = 'Jean';
UPDATE color SET hex = '#C8A2C8' WHERE color = 'Lila Fte';
UPDATE color SET hex = '#FFCC4D' WHERE color = 'Mango';
UPDATE color SET hex = '#2C2C2C' WHERE color = 'Negro flor';
UPDATE color SET hex = '#E8E8E8' WHERE color = 'Melange 3% Rata';
UPDATE color SET hex = '#F5F5F5' WHERE color = 'Melange Blanqueo';
UPDATE color SET hex = '#FFF8DC' WHERE color = 'Melange Cremoso 1%';
UPDATE color SET hex = '#E8E8E8' WHERE color = 'Melange Lavado';
UPDATE color SET hex = '#EFEFEF' WHERE color = 'Melange OP';
UPDATE color SET hex = '#FFDB58' WHERE color = 'Mostaza';
UPDATE color SET hex = '#E1AD01' WHERE color = 'Mostaza 01';
UPDATE color SET hex = '#C49102' WHERE color = 'Mostaza 02';
UPDATE color SET hex = '#FF8C00' WHERE color = 'Naranja Bte';
UPDATE color SET hex = '#0073E6' WHERE color = 'Palace Blue';
UPDATE color SET hex = '#E7C6A5' WHERE color = 'Palo Rosa SM';
UPDATE color SET hex = '#696969' WHERE color = 'Plomo Gris';
UPDATE color SET hex = '#006400' WHERE color = 'V. Oscuro';
UPDATE color SET hex = '#D2691E' WHERE color = 'Rojo Teja';
UPDATE color SET hex = '#FF007F' WHERE color = 'Rose';
UPDATE color SET hex = '#C0C0C0' WHERE color = 'Silver';
UPDATE color SET hex = '#AFEEEE' WHERE color = 'Turqueza Claro';
UPDATE color SET hex = '#1A4D2E' WHERE color = 'V. Botella Jas';
UPDATE color SET hex = '#8FA99C' WHERE color = 'V. Cemento BB';
UPDATE color SET hex = '#90EE90' WHERE color = 'V. Claro';
UPDATE color SET hex = '#50C878' WHERE color = 'V. Esmeralda';
UPDATE color SET hex = '#007BA7' WHERE color = 'V. Galapagos';
UPDATE color SET hex = '#7CFC00' WHERE color = 'V. Gras';
UPDATE color SET hex = '#00613C' WHERE color = 'V. Gucci';
UPDATE color SET hex = '#BFFF00' WHERE color = 'V. Limon';
UPDATE color SET hex = '#979797' WHERE color = 'Cemento Bajo';
UPDATE color SET hex = '#8F00FF' WHERE color = 'Uva';
UPDATE color SET hex = '#F0C4A5' WHERE color = 'Palo Rosa Bajo';
UPDATE color SET hex = '#8B9370' WHERE color = 'Aceituna Bajo';
UPDATE color SET hex = '#FFB76B' WHERE color = 'Chicha Bajo';
UPDATE color SET hex = '#E3CDA4' WHERE color = 'Duna';
UPDATE color SET hex = '#009B7D' WHERE color = 'V. Brasil';
UPDATE color SET hex = '#7FFF00' WHERE color = 'V. Perico G';
UPDATE color SET hex = '#5C9FCC' WHERE color = 'Azulejo';
UPDATE color SET hex = '#FA8072' WHERE color = 'Salmon';
UPDATE color SET hex = '#FFF0F5' WHERE color = 'Yogurt';
UPDATE color SET hex = '#800080' WHERE color = 'Barny';
UPDATE color SET hex = '#708090' WHERE color = 'ACERO POLY';
UPDATE color SET hex = '#F3E5AB' WHERE color = 'Vainilla';
UPDATE color SET hex = '#FFB6D9' WHERE color = 'Rosa BB';
UPDATE color SET hex = '#FFE4E1' WHERE color = 'Pink mist';
UPDATE color SET hex = '#967969' WHERE color = 'Moka';
UPDATE color SET hex = '#4A4A4A' WHERE color = 'Dark Melange';
UPDATE color SET hex = '#1C3A3A' WHERE color = 'V. Petroleo';
UPDATE color SET hex = '#FFFAFA' WHERE color = 'Snowwhite';
UPDATE color SET hex = '#808080' WHERE color = 'Plomo Inter';
UPDATE color SET hex = '#4A5F6F' WHERE color = 'Gargoli';
UPDATE color SET hex = '#DE3163' WHERE color = 'Cereza';
UPDATE color SET hex = '#B565D8' WHERE color = 'Uva claro';
UPDATE color SET hex = '#F0D5C4' WHERE color = 'Palo Rosa BB';
UPDATE color SET hex = '#8A9A5B' WHERE color = 'V. Musgo';
UPDATE color SET hex = '#4B5F8F' WHERE color = 'Azulino indigo';
UPDATE color SET hex = '#6495ED' WHERE color = 'Azul bajo';
UPDATE color SET hex = '#6B8E23' WHERE color = 'Laurel';
UPDATE color SET hex = '#FF77AA' WHERE color = 'Chicle 1';
UPDATE color SET hex = '#B0E0E6' WHERE color = 'V. Agua bb 1';
UPDATE color SET hex = '#FFD700' WHERE color = 'Seguimiento';
UPDATE color SET hex = '#DCA57D' WHERE color = 'Beige Intenso';
UPDATE color SET hex = '#3C4E5F' WHERE color = 'Acero Osc 1';
UPDATE color SET hex = '#FF0033' WHERE color = 'Rojo Brillante';
UPDATE color SET hex = '#B0D8E8' WHERE color = 'Celeste BB 2';
UPDATE color SET hex = '#FF4466' WHERE color = 'Fresa int';
UPDATE color SET hex = '#FFCBA4' WHERE color = 'Durazno';
UPDATE color SET hex = '#A0A0A0' WHERE color = 'Cemento New';
UPDATE color SET hex = '#8B3A62' WHERE color = 'Conchevino 2';
UPDATE color SET hex = '#FFC0D9' WHERE color = 'Rosado BB 2';
UPDATE color SET hex = '#9ACD32' WHERE color = 'V. Amarillento';
UPDATE color SET hex = '#9C6B4E' WHERE color = 'Avellana';
UPDATE color SET hex = '#E0B0FF' WHERE color = 'Malva';
UPDATE color SET hex = '#F5DEB3' WHERE color = 'Beige Carne';
UPDATE color SET hex = '#DC143C' WHERE color = 'ROJO NV R';
UPDATE color SET hex = '#800020' WHERE color = 'Borgoña Piero';
UPDATE color SET hex = '#E8D5C4' WHERE color = 'Beige Intermedio';
UPDATE color SET hex = '#A68862' WHERE color = 'Avellana 2';
UPDATE color SET hex = '#6A8CAF' WHERE color = 'Gargoli Claro';
UPDATE color SET hex = '#9B9B9B' WHERE color = 'Humo';
UPDATE color SET hex = '#6B8E23' WHERE color = 'Olivo';
UPDATE color SET hex = '#F5F0E8' WHERE color = 'Beige Claro';
UPDATE color SET hex = '#722F37' WHERE color = 'Red Wine';
UPDATE color SET hex = '#E63946' WHERE color = 'Samba (Rojo)';
UPDATE color SET hex = '#8B00FF' WHERE color = 'Purple Piero';
UPDATE color SET hex = '#FFFF00' WHERE color = 'Amarillo Piero';
UPDATE color SET hex = '#FF69B4' WHERE color = 'Pink Piero';
UPDATE color SET hex = '#FFCBA4' WHERE color = 'Melon Piero';
UPDATE color SET hex = '#E6B8D0' WHERE color = 'Endenisse';
UPDATE color SET hex = '#E0B0FF' WHERE color = 'Mauve';
UPDATE color SET hex = '#F0F8FF' WHERE color = 'Crystal';
UPDATE color SET hex = '#FF0000' WHERE color = 'rojo rx';
UPDATE color SET hex = '#3A4F68' WHERE color = 'jetty blue';
UPDATE color SET hex = '#2C5E8C' WHERE color = 'Italiano 2';
UPDATE color SET hex = '#F0C4B4' WHERE color = 'Palo Rosa 2';
UPDATE color SET hex = '#00A86B' WHERE color = 'Jade';
UPDATE color SET hex = '#D32F2F' WHERE color = 'mission red';
UPDATE color SET hex = '#6B8E23' WHERE color = 'elm green';
UPDATE color SET hex = '#FFD700' WHERE color = 'gold finch';
UPDATE color SET hex = '#4A90E2' WHERE color = 'gulf blue';
UPDATE color SET hex = '#FF5722' WHERE color = 'signal orange';
UPDATE color SET hex = '#1C1C1C' WHERE color = 'flint black';
UPDATE color SET hex = '#4A5859' WHERE color = 'Basalt';
UPDATE color SET hex = '#E9C893' WHERE color = 'Sahara';
UPDATE color SET hex = '#E0F2F7' WHERE color = 'Hielo';
UPDATE color SET hex = '#98FF98' WHERE color = 'V. Menta';

UPDATE color_x_cliente
SET hex=c.hex
FROM color c
WHERE color_x_cliente.color_id = c.id;

END;


-- ============================================================================
-- 1. MASTER DATA MIGRATION - Public Schema
-- ============================================================================
-- TRUNCATE item_insumo_detalle, item_rollo_detalle, item CASCADE;

-- ============================================================================
-- MIGRAR INSUMOS
-- First: OVERRIDING SYSTEM VALUE preserves insumo.id directly as item.id.
-- setval after advances the sequence so roll items never collide.
-- ============================================================================
WITH base AS (
    SELECT
        i.id                                                              AS insumo_id,
        'I-' ||
        CASE tipo
            WHEN 'directo'  THEN 'COL'
            WHEN 'reactivo' THEN 'COL'
            WHEN 'disperso' THEN 'COL'
            WHEN 'auxiliar' THEN 'AUX'
            WHEN 'quimico'  THEN 'QUIM' END || '-' ||
        CASE tipo
            WHEN 'directo'  THEN 'DIR-'
            WHEN 'reactivo' THEN 'RX-'
            WHEN 'disperso' THEN 'DISP-'
            ELSE '' END ||
        trim(both '-' from regexp_replace(regexp_replace(UPPER(i.insumo) COLLATE "C", '\s+', ' ', 'g'), '[^A-Z0-9]+', '-', 'g'))
                                                                          AS codigo,
        i.insumo                                                          AS nombre,
        u.id                                                              AS unidad_id,
        i.medida,
        it.id                                                             AS item_tipo_id,
        it2.id                                                            AS insumo_tipo_id,
        ct.id                                                             AS colorante_tipo_id
    FROM insumo i
    LEFT JOIN item_tipo    it  ON it.codigo  = 'INSUMO'
    LEFT JOIN unidad       u   ON u.codigo   = 'kg'
    LEFT JOIN insumo_tipo  it2 ON it2.codigo = CASE tipo
        WHEN 'directo'  THEN 'COL'
        WHEN 'reactivo' THEN 'COL'
        WHEN 'disperso' THEN 'COL'
        WHEN 'auxiliar' THEN 'AUX'
        WHEN 'quimico'  THEN 'QUIM' END
    LEFT JOIN colorante_tipo ct ON ct.codigo = CASE tipo
        WHEN 'directo'  THEN 'DIR'
        WHEN 'reactivo' THEN 'RX'
        WHEN 'disperso' THEN 'DISP'
        ELSE NULL END
),
ins AS (
    INSERT INTO item (
        id,
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre
    )
    OVERRIDING SYSTEM VALUE
    SELECT
        b.insumo_id,
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW()
    FROM base b
    RETURNING id, codigo
)
INSERT INTO item_insumo_detalle (
    item_id,
    medida,
    insumo_tipo_id,
    colorante_tipo_id,
    fyh_cre
)
SELECT
    ins.id,
    b.medida,
    b.insumo_tipo_id,
    b.colorante_tipo_id,
    NOW()
FROM ins
JOIN base b ON b.codigo = ins.codigo;

-- Item 13 is purchased as solid but recipes reference it in diluted form (1:6 ratio).
-- factor_stock = 1/6 so generar_receta yields the correct solid-equivalent kg.
UPDATE item_insumo_detalle SET factor_stock = 1.0/6.0 WHERE item_id = 13;

-- Advance sequence so roll items get IDs above all insumo IDs
SELECT setval(pg_get_serial_sequence('item', 'id'), (SELECT MAX(id) FROM item));

-- ============================================================================
-- CREAR ROLLOS 
-- ============================================================================
-- Preview (SELECT only, not inserted):
-- SELECT UPPER('R-' || a.codigo || '-' || COALESCE(a.fibra::text, '1') || '-C') codigo,
-- 'Rollo ' || a.nombre || ' ' || COALESCE(a.fibra, 1) || ' fibra(s) Crudo' nombre,
-- u.id unidad_id, it.id item_tipo_id, p.articulo_id, COALESCE(a.fibra, 1) fibra
-- FROM partida p JOIN articulo a ON a.id = p.articulo_id
-- JOIN item_tipo it ON it.codigo='ROLLO' JOIN unidad u ON u.codigo = 'kg'
-- GROUP BY 1,2,3,4,5,6;

WITH base AS (
   SELECT  UPPER('R-' || a.codigo || '-' || COALESCE(a.fibra::text, '1')) codigo,
'Rollo ' || a.nombre || ' ' || COALESCE(a.fibra, 1) || ' fibra(s)' nombre,
u.id unidad_id,
it.id item_tipo_id,
p.articulo_id,
COALESCE(a.fibra, 1) fibra
FROM partida p
JOIN articulo  a ON a.id = p.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
GROUP BY
UPPER('R-' || a.codigo || '-' || COALESCE(a.fibra::text, '1')),
'Rollo ' || a.nombre || ' ' || COALESCE(a.fibra, 1) || ' fibra(s)',
u.id, it.id, p.articulo_id, COALESCE(a.fibra, 1)
),
ins_item AS (
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW()
    FROM base b
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

-----MIGRAR ROLLOS RIB CRUDOS

WITH base AS (
   SELECT  UPPER('R-RB-' || a.codigo || '-' || COALESCE(a.fibra::text, '1')) codigo,
'Rollo Rib ' || a.nombre || ' ' || COALESCE(a.fibra, 1) || ' fibra(s)' nombre,
u.id unidad_id,
it.id item_tipo_id,
p.articulo_id,
COALESCE(a.fibra, 1) fibra
FROM partida p
JOIN articulo  a ON a.id = p.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
WHERE p.rib > 0
GROUP BY
UPPER('R-RB-' || a.codigo || '-' || COALESCE(a.fibra::text, '1')),
'Rollo Rib ' || a.nombre || ' ' || COALESCE(a.fibra, 1) || ' fibra(s)',
u.id, it.id, p.articulo_id, COALESCE(a.fibra, 1)
),
ins_item AS (
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW()
    FROM base b
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    flg_rib,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);



-- ============================================================================
-- CREAR ALMACENES
-- ============================================================================

INSERT INTO inventario.almacen(codigo,nombre,fyh_cre)
VALUES ('ALM_INS', 'Almacén de Insumos', NOW()),
       ('ALM_CRU', 'Almacén de Crudo', NOW()),
       ('ALM_PT', 'Almacén de Productos Terminados', NOW());

INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,fyh_cre)
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM_INS'
UNION ALL
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM_CRU'
UNION ALL
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM_PT';

-- ============================================================================
-- TERCERO POPULATION (must precede partida, factura_proveedor, compra, guia_remision)
-- ============================================================================
-- id=1 (MLR) already inserted in step 5 with codigo='MLR'.
-- Proveedores and clientes are entirely separate populations (no entity in both).
-- All normalisation in CTEs; INSERT at end of each block.
-- Code formula: UPPER(strip non-alphanum) capped at 20; suffix _{id} on collision.
-- cliente_id2: bridges the MLR/X alias — "MLR/Rudy" and "Rudy" collapse into one
--   tercero row with cliente_id = Rudy's id, cliente_id2 = MLR/Rudy's id.
--   NULL when no MLR/X alias exists for that client.
-- Bridge columns (proveedor_id, cliente_id, cliente_id2) dropped after migration.

-- ── PROVEEDORES ──────────────────────────────────────────────────────────────
WITH all_prov AS (
    SELECT
        id,
        proveedor,
        lower(regexp_replace(proveedor, '[^a-zA-Z0-9]', '', 'g'))  AS name_key,
        COALESCE(fyh_cre_tz, fyh_cre::timestamptz, now())          AS fyh_cre
    FROM proveedor
),
with_code AS (
    SELECT *,
        COALESCE(NULLIF(LEFT(UPPER(name_key), 20), ''), 'PROV' || id::text) AS code_base
    FROM all_prov
),
deduped AS (
    SELECT *, COUNT(*) OVER (PARTITION BY code_base) AS cnt
    FROM with_code
)
INSERT INTO tercero (proveedor_id, codigo, nombre, flg_proveedor, fyh_cre)
SELECT
    id,
    CASE WHEN cnt > 1 OR EXISTS (SELECT 1 FROM tercero WHERE codigo = d.code_base)
         THEN d.code_base || '_' || id::text
         ELSE d.code_base
    END,
    proveedor,
    true,
    fyh_cre
FROM deduped d
ORDER BY id;


-- ── CLIENTES ─────────────────────────────────────────────────────────────────
WITH all_cli AS (
    SELECT
        id,
        regexp_replace(cliente, '^(MLR|OSWALDO)/', '', 'i')                                                    AS nombre_canon,
        lower(regexp_replace(regexp_replace(cliente, '^(MLR|OSWALDO)/', '', 'i'), '[^a-zA-Z0-9]', '', 'g'))   AS name_key,
        CASE WHEN cliente NOT ILIKE 'MLR/%' AND cliente NOT ILIKE 'OSWALDO/%' THEN id END      AS cli_id,   -- plain X
        CASE WHEN cliente ILIKE 'MLR/%' OR  cliente ILIKE 'OSWALDO/%'         THEN id END      AS cli_id2,  -- MLR/X or OSWALDO/X alias
        NULLIF(ruc, '')                                                                         AS ruc,
        NULLIF(correo, '')                                                                      AS correo,
        NULLIF(procedencia, '')                                                                 AS procedencia,
        COALESCE(fyh_cre_tz, fyh_cre::timestamptz, now())                                      AS fyh_cre
    FROM cliente
),
canonical AS (
    -- One row per normalised name; plain X and MLR/X alias collapse into the same group
    SELECT
        name_key,
        COALESCE(
            MIN(CASE WHEN cli_id  IS NOT NULL THEN nombre_canon END),  -- prefer plain spelling
            MIN(nombre_canon)
        )                                                                       AS nombre,
        COALESCE(
            MIN(CASE WHEN cli_id  IS NOT NULL THEN id END),             -- plain X id as primary
            MIN(CASE WHEN cli_id2 IS NOT NULL THEN id END)              -- MLR/X-only fallback
        )                                                                       AS primary_id,
        -- Secondary id only when both plain X and MLR/X exist in the legacy table
        CASE WHEN COUNT(CASE WHEN cli_id IS NOT NULL THEN 1 END) > 0
             THEN MIN(CASE WHEN cli_id2 IS NOT NULL THEN id END)
        END                                                                     AS secondary_id,
        -- Contact info: prefer plain row, fall back to alias row
        COALESCE(MAX(CASE WHEN cli_id IS NOT NULL THEN ruc         END), MAX(ruc))    AS ruc,
        COALESCE(MAX(CASE WHEN cli_id IS NOT NULL THEN correo      END), MAX(correo)) AS correo,
        -- procedencia = MLR whenever the group has an MLR/ or OSWALDO/ alias
        CASE WHEN COUNT(CASE WHEN cli_id2 IS NOT NULL THEN 1 END) > 0
             THEN 'MLR'
             ELSE COALESCE(MAX(CASE WHEN cli_id IS NOT NULL THEN procedencia END), MAX(procedencia))
        END                                                                            AS procedencia,
        MIN(fyh_cre)                                                                   AS fyh_cre
    FROM all_cli
    GROUP BY name_key
),
with_code AS (
    SELECT *,
        COALESCE(NULLIF(LEFT(UPPER(name_key), 20), ''), 'CLI' || primary_id::text) AS code_base
    FROM canonical
)
INSERT INTO tercero (cliente_id, cliente_id2, codigo, nombre, ruc, correo, procedencia, flg_cliente, fyh_cre)
SELECT
    w.primary_id,
    w.secondary_id,
    w.code_base,   -- no collision-avoidance: UNIQUE constraint on tercero.codigo will catch duplicates
    w.nombre,
    w.ruc,
    w.correo,
    w.procedencia,
    true,
    w.fyh_cre
FROM with_code w
WHERE NOT EXISTS (SELECT 1 FROM tercero t WHERE t.codigo = w.code_base)
ORDER BY w.primary_id;

-- Bridge MLR's legacy cliente_id so the roll backfill JOIN resolves propietario_id = 1
-- for all partidas owned by MLR (public.cliente.id = 13 = 'MLR').
UPDATE tercero SET cliente_id = 13 WHERE id = 1;

-- Populate color_x_cliente.tercero_id now that tercero has its cliente_id bridges set.
UPDATE color_x_cliente cxc
SET tercero_id = t.id
FROM tercero t
WHERE t.cliente_id = cxc.cliente_id
   OR t.cliente_id2 = cxc.cliente_id;
---CHECK 

SELECT p.id, p.cliente_id FROM public.partida p
LEFT JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
WHERE p.rollos > 0 AND p.peso_rollos > 0 AND t.id IS NULL;

-- ============================================================================
-- MIGRAR PARTIDAS
-- ============================================================================
-- Correct column types if 04_alter_legacy_tables ran with legacy partida_estado_enum.
ALTER TABLE estado DROP COLUMN IF EXISTS estado_produccion;
ALTER TABLE estado DROP COLUMN IF EXISTS estado_comercial;
ALTER TABLE estado ADD COLUMN IF NOT EXISTS estado_produccion partida_estado_produccion_enum;
ALTER TABLE estado ADD COLUMN IF NOT EXISTS estado_comercial  partida_estado_comercial_enum;

--Mapear Estados existentes
-- SELECT '''' || estado || '''' AS estado FROM estado
UPDATE partida
SET fyh_cre_tz=fyh_cre + INTERVAL '5 hours'
WHERE fyh_cre_tz='2025-09-11 22:53:28.212517+00';
UPDATE estado
SET estado_produccion = CASE estado
    WHEN 'Para Programar'      THEN 'CREADA'::partida_estado_produccion_enum
    WHEN 'Programado'          THEN 'PROGRAMADA'::partida_estado_produccion_enum
    WHEN 'En Proceso Teñido'   THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Teñido'              THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Lavado Hidro'        THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Secado'              THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Para Despachar'      THEN 'TECO'::partida_estado_produccion_enum
    WHEN 'Despachado'          THEN 'CERRADA'::partida_estado_produccion_enum
    WHEN 'Devolución'          THEN 'CERRADA'::partida_estado_produccion_enum
    WHEN 'Observado'           THEN 'TECO'::partida_estado_produccion_enum
    WHEN 'Reprocesado'         THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'En Proceso Repartida' THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Planchado'           THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Replanchado'         THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Termofijado'         THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    WHEN 'Perchado'            THEN 'EN_PRODUCCION'::partida_estado_produccion_enum
    ELSE                            'CERRADA'::partida_estado_produccion_enum
END,
estado_comercial = CASE estado
    WHEN 'Para Programar'      THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Programado'          THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'En Proceso Teñido'   THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Teñido'              THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Lavado Hidro'        THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Secado'              THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Para Despachar'      THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Despachado'          THEN 'ENTREGADA'::partida_estado_comercial_enum
    WHEN 'Devolución'          THEN 'DEVUELTA_PARCIAL'::partida_estado_comercial_enum
    WHEN 'Observado'           THEN 'ENTREGADA'::partida_estado_comercial_enum
    WHEN 'Reprocesado'         THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'En Proceso Repartida' THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Planchado'           THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Replanchado'         THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Termofijado'         THEN 'PENDIENTE'::partida_estado_comercial_enum
    WHEN 'Perchado'            THEN 'PENDIENTE'::partida_estado_comercial_enum
    ELSE                            'PENDIENTE'::partida_estado_comercial_enum
END;
    
WITH ult_estado as(SELECT ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY id desc) rw,* FROM partida_estado_historial)
,base as(SELECT 
pp.id,
pp.codigo,pp.prioridad_id,pp.cliente_id,
pp.color_x_cliente_id,
pp.tenido_id,
pp.articulo_id, pp.malla,pp.rendimiento,
pp.ancho,
pp.rib,
pp.rollos,
pp.fibra,
e.estado,
e.estado_comercial,
e.estado_produccion,
pp.fecha_registro,
pp.fecha_entrega,
pp.usr_cre,
pp.fyh_cre_tz
FROM public.partida pp
LEFT JOIN ult_estado ue ON pp.id = ue.partida_id AND rw=1
LEFT JOIN estado e ON ue.estado_id = e.id)
,ins_partida as(
   INSERT INTO mes.partida (
    id,
    numero,
    prioridad_id,
    tercero_id,
    color_x_cliente_id,
    tenido_id,
    articulo_tipo_id,
    fibra,
    malla,
    rendimiento,
    ancho,
    estado_produccion,
    estado_comercial,
    fecha_acordada,
    fyh_programacion,
    fyh_inicio,
    fyh_fin,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    p.id,          -- same id as old partida
    p.codigo,
    p.prioridad_id,
    (SELECT t.id FROM tercero t WHERE t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id),  -- bridge: covers both plain X and MLR/X aliases
    p.color_x_cliente_id,
    p.tenido_id,
    (SELECT a.articulo_tipo_id FROM articulo a WHERE a.id = p.articulo_id),
    (SELECT a.fibra            FROM articulo a WHERE a.id = p.articulo_id),
    p.malla,
    p.rendimiento,
    p.ancho,
    COALESCE(p.estado_produccion, 'CREADA'::partida_estado_produccion_enum),
    COALESCE(p.estado_comercial,  'PENDIENTE'::partida_estado_comercial_enum),
    p.fecha_entrega,
    p.fecha_registro::TIMESTAMP + INTERVAL '5 hours',
    p.fecha_registro::TIMESTAMP + INTERVAL '5 hours',
    -- fyh_fin: only set when the order is genuinely closed AND fecha_entrega has
    -- already passed. A future fecha_entrega means dispatch hasn't happened yet
    -- → NULL is correct; the function will set it when the partida actually closes.
    -- Use (fecha_entrega + 1 day) to place fyh_fin at the start of the following
    -- day, guaranteeing it is always after fyh_inicio even when both fall on the
    -- same calendar date (fecha_entrega midnight+5h would precede an afternoon
    -- fyh_inicio derived from fecha_registro, producing a negative duration).
    CASE WHEN COALESCE(p.estado_produccion, 'CREADA') IN ('CERRADA', 'TECO')
              AND p.fecha_entrega < CURRENT_DATE
         THEN (p.fecha_entrega + 1)::TIMESTAMP + INTERVAL '5 hours'
         ELSE NULL
    END,
    p.usr_cre,
    p.fyh_cre_tz
FROM base p
RETURNING id
)    INSERT INTO mes.partida_detalle (
        partida_id,
        item_id,
        cantidad,
        unidad_id,
        usr_cre,
        fyh_cre
    )
    SELECT
        p.id,
        ird.item_id,
        CASE WHEN ird.flg_rib THEN p.rib ELSE p.rollos END,
        (SELECT id FROM unidad WHERE codigo = 'UN'),
        p.usr_cre,
        p.fyh_cre_tz
    FROM base p
    JOIN item_rollo_detalle ird
    ON ird.articulo_id=p.articulo_id AND (ird.flg_rib=false OR (ird.flg_rib AND p.rib>0));
SELECT setval(
  pg_get_serial_sequence('mes.partida', 'id'),
  (SELECT MAX(id) FROM mes.partida)
);
SELECT setval(
  pg_get_serial_sequence('mes.partida', 'numero'),
  (SELECT MAX(numero) FROM mes.partida)
);


--============================================
--EJECUTAR ESTA SECCION MANUALMENTE
--============================================
UPDATE mes.partida SET flg_antipilling=(CASE p.adicional_id WHEN 1 THEN true ELSE false END) FROM partida p WHERE p.id=mes.partida.id;


-- Replaced by combined 1-pxr → 1-orden → 1-paso CTE below (after tipo_receta setup).
-- TRUNCATE here so re-runs are safe and the combined insert starts clean.
-- TRUNCATE mes.partida CASCADE;
--===========================================
--Migrar pasos
--===========================================
-- SELECT * FROM tipo_receta;
-- Add column with FK
ALTER TABLE tipo_receta ADD COLUMN operacion_id SMALLINT;
ALTER TABLE tipo_receta ADD CONSTRAINT fk_tipo_receta_operacion 
    FOREIGN KEY (operacion_id) REFERENCES mes.operacion(id);

-- Update statements
UPDATE tipo_receta SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')
WHERE tipo_receta IN ('Teñido', 'Reteñido', 'Teñido a Negro', 'Desmontado + Reteñido', 'Repartida Matizado');

UPDATE tipo_receta SET operacion_id = (SELECT id FROM mes.operacion WHERE codigo = 'LAVADO_HIDRO')
WHERE tipo_receta IN (
    'Rebaje', 'Mojar', 'Lavado x Lineas', 'Lavado x Lineas Suavizante',
    'Lavado x Suavidad', 'Lavado x Manchas', 'Lavado x Migrado',
    'Lavado x Quebradura', 'Lavado x Fijado', 'Lavado Hidrofilo'
);

-----------------TERMINAR DE CONFIGUARAR MAQUINAS ANTES DE MIGRAR PASOS
-- ============================================================================
-- MIGRATE MAQUINAS
-- ============================================================================

-- First, create maquina_tipo entries based on ubicacion values
INSERT INTO mes.maquina_tipo (codigo, nombre) VALUES
('TEN',     'Maquina de Teñido'),
('HIDRO',   'Hidroextractora'),
('COMPACT', 'Compactadora'),
('PERCH',   'Perchadora'),
('PREP',    'Preparadora'),
('SEC',     'Secadora'),
('TERMO',   'Termofijadora'),
('VOLT',    'Volteadora'),
('BOMBA',   'Bomba de Agua'),
('POZO',    'Pozo de Agua'),
('ABLAND',  'Ablandador'),
('COMPR',   'Compresor'),
('CALDERO', 'Caldero')
ON CONFLICT (codigo) DO NOTHING;

-- Migrate maquina records with preserved IDs
-- codigo is omitted: auto-gen trigger (fn_trg_gen_codigo_maquina) derives it
-- from maquina_tipo.codigo + per-type sequence → e.g. TEN-001, SEC-001
INSERT INTO mes.maquina (
    id,
    nombre,
    maquina_tipo_id,
    capacidad_min_kg,
    capacidad_max_kg,
    relacion_bano,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    m.id,
    m.nombre,
    CASE m.ubicacion
        WHEN 'Maq Teñido'         THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'TEN')
        WHEN 'Hidro'              THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'HIDRO')
        WHEN 'Compactadora'       THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'COMPACT')
        WHEN 'Percha'             THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'PERCH')
        WHEN 'Preparadora'        THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'PREP')
        WHEN 'Secadora'           THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'SEC')
        WHEN 'Termofijadora'      THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'TERMO')
        WHEN 'Volteadora'         THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'VOLT')
        WHEN 'Bombas de Agua'     THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'BOMBA')
        WHEN 'Pozo/Falta de Agua' THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'POZO')
        WHEN 'Ablandador'         THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'ABLAND')
        WHEN 'Compresor'          THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'COMPR')
        WHEN 'Caldero'            THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'CALDERO')
    END AS maquina_tipo_id,
    -- Estimated capacities based on machine type and RB
    CASE 
        WHEN m.ubicacion = 'Maq Teñido' AND m."RB" = 7 THEN 50   -- Larger dyeing machine
        WHEN m.ubicacion = 'Maq Teñido' AND m."RB" = 5 THEN 30   -- Standard dyeing machine
        WHEN m.ubicacion = 'Hidro' THEN 50
        WHEN m.ubicacion = 'Secadora' THEN 40
        WHEN m.ubicacion = 'Compactadora' THEN 30
        ELSE 10  -- Default for utility machines
    END AS capacidad_min_kg,
    CASE 
        WHEN m.ubicacion = 'Maq Teñido' AND m."RB" = 7 THEN 200  -- Larger dyeing machine
        WHEN m.ubicacion = 'Maq Teñido' AND m."RB" = 5 THEN 150  -- Standard dyeing machine
        WHEN m.ubicacion = 'Hidro' THEN 180
        WHEN m.ubicacion = 'Secadora' THEN 160
        WHEN m.ubicacion = 'Compactadora' THEN 120
        ELSE 50  -- Default for utility machines
    END AS capacidad_max_kg,
    m."RB" AS relacion_bano,
    NOW() AS fyh_cre
FROM public.maquina m
ORDER BY m.id;

-- Reset the sequence to continue from the max ID
SELECT setval(
    pg_get_serial_sequence('mes.maquina', 'id'),
    (SELECT MAX(id) FROM mes.maquina)
);

-- Verify migration
SELECT 
    m.id,
    m.codigo,
    m.nombre,
    mt.nombre AS tipo,
    m.capacidad_min_kg,
    m.capacidad_max_kg,
    m.relacion_bano
FROM mes.maquina m
LEFT JOIN mes.maquina_tipo mt ON mt.id = m.maquina_tipo_id
ORDER BY m.id;

-- SELECT * FROM mes.operacion;
-- SELECT * FROM partida_x_recetas;
-- SELECT  pxr.partida_id, tr.tipo_receta,pxr.fecha
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- WHERE pxr.partida_id IN (SELECT partida_id FROM partida_x_recetas GROUP BY partida_id HAVING COUNT(*) > 1)
-- AND flg_elm=false AND tipo_receta_id IS NOT NULL
-- ORDER BY 1,3;

-- -----VER los ordenes de los tipos de receta y su incidencia
-- WITH o AS (
--   SELECT  ROW_NUMBER() OVER (PARTITION BY pxr.partida_id ORDER BY pxr.fecha) rw, tr.tipo_receta
--   FROM partida_x_recetas pxr
--   LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
--   WHERE pxr.partida_id IN (SELECT partida_id FROM partida_x_recetas GROUP BY partida_id HAVING COUNT(*) > 1)
--   AND flg_elm=false AND tipo_receta_id IS NOT NULL
-- )
-- SELECT rw, tipo_receta, COUNT(*) FROM o GROUP BY rw, tipo_receta ORDER BY 2,1;
-- ----Ver los casos en los que los teñidos no son la primera receta ejecutada y la causa (fecha)
-- WITH o AS (
--   SELECT  ROW_NUMBER() OVER (PARTITION BY pxr.partida_id ORDER BY pxr.fecha) rw, tr.tipo_receta,pxr.partida_id,fecha, pxr.fyh_cre
--   FROM partida_x_recetas pxr
--   LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
--   WHERE pxr.partida_id IN (SELECT partida_id FROM partida_x_recetas GROUP BY partida_id HAVING COUNT(*) > 1)
--   AND flg_elm=false AND tipo_receta_id IS NOT NULL
--     )SELECT * FROM o WHERE partida_id IN (SELECT partida_id FROM o WHERE rw=1 AND tipo_receta!='Teñido')
------Casos que tienen  ejecuciones de receta sin orden de produccion
-- WITH o AS (
-- SELECT op.id,pxr.partida_id
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- LEFT JOIN mes.partida op ON op.partida_id = pxr.partida_id 
-- AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
-- WHERE op.id IS NULL
-- )SELECT DISTINCT tipo FROM mes.partida WHERE partida_id IN (SELECT partida_id FROM o)

------- Ver breakdown de los casos/ orden de ejecucion para ver si son parte de la produccion normal o repartidas no registrados
-- WITH o AS (
-- SELECT op.id,pxr.partida_id
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- LEFT JOIN mes.partida op ON op.partida_id = pxr.partida_id 
-- AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
-- WHERE op.id IS NULL
-- )SELECT  pxr.partida_id, tr.tipo_receta,pxr.fecha
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- WHERE pxr.partida_id IN (SELECT partida_id FROM partida_x_recetas GROUP BY partida_id HAVING COUNT(*) > 1)
-- AND flg_elm=false AND tipo_receta_id IS NOT NULL AND partida_id IN (SELECT partida_id FROM o)
-- ORDER BY 1,3; 
-----SE CONFIRMA QUE TODOS LOS QUE nO JOINEAN SON PROQUE SON REPROCESOS O AJUSTES NO REGISTRADOS COMO TAL
-- (Stale patch block removed — superseded by 1:1:1 combined CTE above)

-- ============================================================================
-- MIGRAR RECETAS
-- Pre-migration prep: stage parsed values into public.receta_paso
-- (ALTER TABLE is transactional in PostgreSQL — runs inside BEGIN block)
-- ============================================================================

-- Step 1: Add staging columns to source table
ALTER TABLE public.paso
    ADD COLUMN IF NOT EXISTS op_id      SMALLINT,
    ADD COLUMN IF NOT EXISTS ph_val     NUMERIC(4,2),
    ADD COLUMN IF NOT EXISTS temp_val   NUMERIC(5,2),
    ADD COLUMN IF NOT EXISTS tiempo_val SMALLINT;

-- Step 2: Auto-populate via CASE + regex
UPDATE public.paso SET
    op_id = CASE
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%TINTURA%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%TENIDO%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%TENIR%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%TNTURA%'             THEN 1  -- TINTURA
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%LAVADO%REDUCTIVO%'   THEN 3  -- LAVADO_REDUCTIVO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%BLANQUEO%OPTICO%'    THEN 5  -- BLANQUEO_OPTICO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%BLANQUEO%'
          OR unaccent(upper(paso COLLATE "C")) LIKE 'B.QUIM%'              THEN 4  -- BLANQUEO_QUIMICO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%LAVADO%'             THEN 2  -- LAVADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%DESCRUDE%'           THEN 6  -- DESCRUDE
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%NEUTRALIZA%'         THEN 7  -- NEUTRALIZADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%FIJADO%'             THEN 9  -- FIJADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%SUAVIZADO%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%SUAVIZANTE%'         THEN 8  -- SUAVIZADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%JABONADO%'           THEN 10 -- JABONADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%ENJUAGUE%'           THEN 11 -- ENJUAGUE
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%MATIZ%'              THEN 12 -- MATIZADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%ANTIPILLING%'        THEN 13 -- ANTIPILLING
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%SIMULTANEO%'         THEN 15 -- SIMULTANEO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%REGULAR%PH%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%REGULACION%PH%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%REGULANDO%PH%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%REGULO%PH%'
          OR unaccent(upper(paso COLLATE "C")) LIKE 'CHECK%PH%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%NO REGULAR%'         THEN 14 -- REGULACION_PH
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%DESMONTADO%'
          OR unaccent(upper(paso COLLATE "C")) LIKE '%ELIMINACI%'          THEN 16 -- DESMONTADO
        WHEN unaccent(upper(paso COLLATE "C")) LIKE '%REBAJE%'             THEN 17 -- REBAJE
        ELSE NULL
    END,
    ph_val    = (regexp_match(upper(paso COLLATE "C"), 'PH\s*[=:]?\s*(\d+(?:[.,]\d+)?)'))[1]::numeric(4,2),
    temp_val  = (regexp_match(paso COLLATE "C", '(\d{2,3})\s*[°º]'))[1]::numeric(5,2),
    tiempo_val = COALESCE(
        ( (regexp_match(lower(paso COLLATE "C"), '(\d+):(\d+)\s*min'))[1]::smallint * 60
        + (regexp_match(lower(paso COLLATE "C"), '(\d+):(\d+)\s*min'))[2]::smallint ),
        (regexp_match(lower(paso COLLATE "C"), '(\d+)\s*hora'))[1]::smallint * 60,
        (regexp_match(lower(paso COLLATE "C"), '(\d+)\s*min'))[1]::smallint,
        (regexp_match(paso COLLATE "C", $$(\d+)\s*'$$))[1]::smallint
    );

-- Step 3: Manual corrections for unmapped rows
UPDATE public.paso SET op_id = 1 WHERE id = 163; -- PH 8.5-9 CON COLORANTE A 110°C X 20' → TINTURA
UPDATE public.paso SET op_id = 1 WHERE id = 165; -- A 90°C PH 10 CON SAL X 20' → TINTURA


--TRUNCATE receta.tenido CASCADE;
-- 1. receta.tenido (preserves legacy IDs from public.receta2)
INSERT INTO receta.tenido (
    id,
    color_x_cliente_id,
    articulo_tipo_id,
    fibra,
    tenido_id,
    flg_antipilling,
    tipo_receta_id,
    estado_id,
    fyh_produccion,
    usr_cre, fyh_cre
)
OVERRIDING SYSTEM VALUE
WITH ranked AS (
    -- Among duplicate approved recipes for the same key, only the latest id keeps APROBADO.
    -- All earlier approved versions are demoted to HISTORICO.
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY color_x_cliente_id, tipo_articulo_id, fibra, tenido_id, flg_antipilling
               ORDER BY id DESC
           ) AS rn
    FROM public.receta2
    WHERE flg_produccion = true
)
SELECT
    r.id,
    r.color_x_cliente_id,
    r.tipo_articulo_id,
    r.fibra,
    r.tenido_id,
    r.flg_antipilling,
    r.tipo_receta_id,
    CASE
        WHEN r.flg_produccion = true AND rk.rn = 1
            THEN (SELECT id FROM estado_desarrollo_color WHERE codigo = 'APROBADO')
        WHEN r.flg_produccion = true
            THEN (SELECT id FROM estado_desarrollo_color WHERE codigo = 'HISTORICO')
        WHEN r.flg_activo = true
            THEN (SELECT id FROM estado_desarrollo_color WHERE codigo = 'EN_DESARROLLO')
        ELSE
            (SELECT id FROM estado_desarrollo_color WHERE codigo = 'CANCELADO')
    END AS estado_id,
    r.fyh_produccion,
    CASE WHEN r.usr_cre NOT IN ('authenticated','anon','postgres') THEN r.usr_cre::integer ELSE NULL END,
    r.fyh_cre
FROM public.receta2 r
LEFT JOIN ranked rk ON rk.id = r.id
ORDER BY r.id;

SELECT setval(
    pg_get_serial_sequence('receta.tenido', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido), 1)
);

-- 2. receta.tenido_paso (staging columns op_id/ph_val/temp_val/tiempo_val used here)
INSERT INTO receta.tenido_paso (
    id,
    receta_id,
    operacion_id,
    orden,
    ph,
    temperatura,
    tiempo_min,
    nota
)
OVERRIDING SYSTEM VALUE
SELECT
    rxp.id,
    rxp.receta_id,
    rp.op_id        AS operacion_id,
    rxp.orden,
    rp.ph_val       AS ph,
    rp.temp_val     AS temperatura,
    rp.tiempo_val   AS tiempo_min,
    rp.paso         AS nota
FROM public.paso rp
JOIN receta_x_paso rxp ON rxp.paso_id = rp.id
WHERE rp.op_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM receta.tenido WHERE id = rxp.receta_id);

SELECT setval(
    pg_get_serial_sequence('receta.tenido_paso', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido_paso), 1)
);

-- 3. receta.tenido_paso_insumo (item.id = insumo.id — preserved via OVERRIDING above)
INSERT INTO receta.tenido_paso_insumo (
    paso_id,
    item_id,
    cantidad,
    orden
)
SELECT
    rxp.id                                                                  AS paso_id,
    it.id                                                                   AS item_id,
    rxi.cantidad,
    ROW_NUMBER() OVER (PARTITION BY rxp.id ORDER BY rxi.orden)             AS orden
FROM public.receta_x_insumo rxi
JOIN item it ON it.id = rxi.insumo_id
JOIN LATERAL (
    SELECT p.id
    FROM receta_x_paso p
    WHERE p.receta_id = rxi.receta_id
      AND p.orden <= rxi.orden
    ORDER BY p.orden DESC
    LIMIT 1
) rxp ON true
WHERE EXISTS (SELECT 1 FROM receta.tenido_paso WHERE id = rxp.id);

SELECT setval(
    pg_get_serial_sequence('receta.tenido_paso_insumo', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.tenido_paso_insumo), 1)
);

-- 4. receta.lavado_maquina
INSERT INTO receta.lavado_maquina (
    id,
    tipo_lavado_mq_id,
    valor_origen_id,
    valor_destino_id,
    flg_activo,
    usr_cre, fyh_cre
)
OVERRIDING SYSTEM VALUE
WITH ranked AS (
    -- Among duplicate active recipes for the same transition, only the latest keeps flg_activo = true.
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY tipo_lavado_mq_id, valor_origen_id, valor_destino_id
               ORDER BY id DESC
           ) AS rn
    FROM public.receta_lavado_maquina
    WHERE flg_activo = true
)
SELECT
    rlm.id,
    rlm.tipo_lavado_mq_id,
    rlm.valor_origen_id,
    rlm.valor_destino_id,
    CASE WHEN rk.rn = 1 THEN true ELSE false END AS flg_activo,
    NULL, rlm.fyh_cre
FROM public.receta_lavado_maquina rlm
LEFT JOIN ranked rk ON rk.id = rlm.id
ORDER BY rlm.id;

SELECT setval(
    pg_get_serial_sequence('receta.lavado_maquina', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.lavado_maquina), 1)
);
-- ── Prep: synthetic row IDs for lavado_maquina junction tables ─────────────
-- Run BEFORE the receta.lavado_maquina_paso / _paso_insumo inserts.

-- 1. Give each (receta_lavado_maquina_id, paso_id) row a stable unique ID
--    — mirrors the id column that receta_x_paso already has.
ALTER TABLE public.receta_lavado_maquina_x_paso
    ADD COLUMN IF NOT EXISTS id SERIAL;

-- 2. Stamp that junction ID onto the insumo table so the migration can
--    join receta_lavado_maquina_paso_insumo → receta_lavado_maquina_x_paso.
--    Adjust the WHERE join columns if the insumo table uses different names.
ALTER TABLE public.receta_lavado_maquina_x_insumo
    ADD COLUMN IF NOT EXISTS id SERIAL;

-- 5. receta.lavado_maquina_paso (staging columns op_id/ph_val/temp_val/tiempo_val used here)
INSERT INTO receta.lavado_maquina_paso (
    id,
    receta_id,
    operacion_id,
    orden,
    ph,
    temperatura,
    tiempo_min,
    nota
)
OVERRIDING SYSTEM VALUE
SELECT
    rlmp.id,
    rlmp.receta_lavado_mq_id   AS receta_id,
    rp.op_id                        AS operacion_id,
    rlmp.orden,
    rp.ph_val                       AS ph,
    rp.temp_val                     AS temperatura,
    rp.tiempo_val                   AS tiempo_min,
    rp.paso                         AS nota
FROM public.receta_lavado_maquina_x_paso rlmp
JOIN public.paso rp ON rp.id = rlmp.paso_id
WHERE rp.op_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM receta.lavado_maquina WHERE id = rlmp.receta_lavado_mq_id);
SELECT setval(
    pg_get_serial_sequence('receta.lavado_maquina_paso', 'id'),
    COALESCE((SELECT MAX(id) FROM receta.lavado_maquina_paso), 1)
);

-- 6. receta.lavado_maquina_paso_insumo
INSERT INTO receta.lavado_maquina_paso_insumo (
    paso_id,
    item_id,
    cantidad,
    orden
)
SELECT
    rlmp.id                                                      AS paso_id,
    it.id                                                        AS item_id,
    rxi.cantidad,
    ROW_NUMBER() OVER (PARTITION BY rlmp.id ORDER BY rxi.orden) AS orden
FROM public.receta_lavado_maquina_x_insumo rxi
JOIN item it ON it.id = rxi.insumo_id
JOIN LATERAL (
    SELECT p.id
    FROM public.receta_lavado_maquina_x_paso p
    WHERE p.receta_lavado_mq_id = rxi.receta_lavado_mq_id
      AND p.orden <= rxi.orden
    ORDER BY p.orden DESC
    LIMIT 1
) rlmp ON true
WHERE EXISTS (SELECT 1 FROM receta.lavado_maquina_paso WHERE id = rlmp.id);

-- ============================================================================
-- END MIGRAR RECETAS
-- ============================================================================
-- ============================================================================
-- MIGRAR ORDENES DE PRODUCCION
-- ============================================================================
-- Source: produccion_tenido (pt) — one row per dyeing run, has accurate
-- timing (hora_inicio/hora_fin) and covers the full history.
--
-- op.id = opp.id = pt.id (OVERRIDING SYSTEM VALUE) so the roll lote backfill
-- can join directly via pt_id without any pxr indirection.
--
-- receta_id / relacion_bano intentionally left NULL here — to be enriched
-- from partida_x_recetas in a later pass once base migration is stable.
--
-- TODO: enrich from pxr:
--   UPDATE mes.partida_paso opp
--   SET receta_id     = pxr.receta_id,
--       relacion_bano = COALESCE(pxr.relacion_bano, m."RB")
--   FROM partida_x_recetas pxr
--   LEFT JOIN public.maquina m ON m.id = pxr.maquina_id
--   WHERE opp.partida_id IN (
--       SELECT op.id FROM mes.partida op
--       JOIN produccion_tenido pt ON pt.id = op.id
--       WHERE pt.partida_id = pxr.partida_id AND pt.maquina::int = pxr.maquina_id
--   );
-- ============================================================================
-- SELECT * FROM produccion_tenido
-- SELECT DISTINCT kilos,estandar FROM produccion_tenido
-- TRUNCATE mes.partida CASCADE;
-- SELECT distinct tipo, tipo_receta
-- FROM produccion_tenido pt
--     JOIN tipo_receta tr ON tr.tipo_receta = pt.tipo

-- TODO: produccion_tenido migration block needs redesign.
-- mes.partida no longer has columns partida_id or tipo (dropped in schema refactor).
-- Each produccion_tenido row is a historical dyeing run that should become a
-- mes.paso_ejecucion under an existing mes.partida_paso, NOT a new mes.partida.
-- Decide: migrate as paso_ejecucion rows (preferred) or rework partidas.
-- Leaving commented out until target structure is confirmed.
--
-- WITH op_insert AS (
--     INSERT INTO mes.partida (id, partida_id, tipo, estado_produccion, estado_comercial, fyh_inicio, fyh_fin, fyh_cre)
--     OVERRIDING SYSTEM VALUE
--     SELECT
--         pt.id,
--         pt.partida_id,       -- structural issue: no such column on mes.partida
--         tr.partida_tipo,  -- no such column on mes.partida
--         CASE WHEN pt.hora_fin IS NOT NULL
--              THEN 'CERRADA'::partida_estado_produccion_enum
--              ELSE 'EN_PRODUCCION'::partida_estado_produccion_enum
--         END,
--         'PENDIENTE'::partida_estado_comercial_enum,
--         (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours',
--         (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours' + pt.duracion::INTERVAL,
--         (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours'
--     FROM produccion_tenido pt
--     JOIN tipo_receta tr ON tr.tipo_receta = pt.tipo
--     WHERE partida_id IN (SELECT id FROM partida)
--     RETURNING id
-- )
-- INSERT INTO mes.partida_paso (
--     id, partida_id, secuencia, operacion_id, maquina_asignada_id,
--     fyh_inicio, fyh_fin, fyh_cre, estado
-- )
-- OVERRIDING SYSTEM VALUE
-- SELECT
--     pt.id,
--     pt.id,
--     1,
--     COALESCE(tr.operacion_id, (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO')),
--     pt.maquina::int,
--     (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours',
--     (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours' + pt.duracion::INTERVAL,
--     (pt.fecha + pt.hora_inicio)::TIMESTAMP + INTERVAL '5 hours',
--     'COMPLETADO'
-- FROM op_insert oi
-- JOIN produccion_tenido pt ON pt.id = oi.id
-- JOIN tipo_receta tr ON tr.tipo_receta = pt.tipo
-- WHERE partida_id IN (SELECT id FROM partida);

-- ============================================================================
-- MIGRAR PARTIDA_PASO  ←  produccion_tenido  (NORMAL runs only)
-- ============================================================================
-- One paso per NORMAL dyeing run, paso.id = pt.id via OVERRIDING SYSTEM VALUE.
-- secuencia = chronological rank among NORMAL runs per partida.
-- REPROCESO runs are handled separately below as rework partidas.
-- ============================================================================
INSERT INTO mes.partida_paso (
    id,
    partida_id,
    secuencia,
    operacion_id,
    maquina_planificada_id,
    receta_id,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    pt.id,
    pt.partida_id,
    ROW_NUMBER() OVER (PARTITION BY pt.partida_id ORDER BY pt.fecha, pt.id)::smallint,
    (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO'),
    pt.maquina::int,
    p.receta_id,
    NULL,
    ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
FROM public.produccion_tenido pt
JOIN public.partida p ON p.id = pt.partida_id
WHERE pt.partida_id IN (SELECT id FROM mes.partida)
  AND pt.tipo = 'Teñido'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- MIGRAR REPROCESOS  ←  produccion_tenido  (REPROCESO runs)
-- ============================================================================
-- Each REPROCESO run becomes its own mes.partida (rework order) with
-- partida_origen_id pointing to the original, copying the original's specs
-- but with the reprocessed roll count from produccion_tenido.
-- Identity auto-increments (no OVERRIDING) since there is no legacy id to preserve.
-- The paso still uses OVERRIDING SYSTEM VALUE (paso.id = pt.id) since pt.id
-- is globally unique across all produccion_tenido rows.
-- Correlation back from the new partida.id to pt.id is via
-- (partida_origen_id, fyh_cre) which is unique per rework row.
-- ============================================================================
INSERT INTO mes.partida (
    partida_origen_id,
    prioridad_id,
    tercero_id,
    tenido_id,
    color_x_cliente_id,
    articulo_tipo_id,
    fibra,
    malla,
    rendimiento,
    ancho,
    flg_antipilling,
    estado_produccion,
    estado_comercial,
    fyh_inicio,
    fyh_fin,
    usr_cre,
    fyh_cre
)
SELECT
    p.id,
    p.prioridad_id,
    p.tercero_id,
    p.tenido_id,
    p.color_x_cliente_id,
    p.articulo_tipo_id,
    p.fibra,
    p.malla,
    p.rendimiento,
    p.ancho,
    p.flg_antipilling,
    'CERRADA'::partida_estado_produccion_enum,
    'PENDIENTE'::partida_estado_comercial_enum,
    ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ,
    CASE WHEN pt.hora_fin IS NOT NULL
         THEN ((pt.fecha + pt.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
         ELSE NULL
    END,
    NULL,
    ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
FROM public.produccion_tenido pt
JOIN mes.partida p ON p.id = pt.partida_id
WHERE pt.tipo != 'Teñido'
  AND pt.partida_id IN (SELECT id FROM mes.partida);

-- Paso for each rework partida — paso.id = pt.id, secuencia always 1 (single step per rework).
-- Joined back to the rework partida via (partida_origen_id, fyh_cre) as correlation key.
INSERT INTO mes.partida_paso (
    id,
    partida_id,
    secuencia,
    operacion_id,
    maquina_planificada_id,
    receta_id,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    pt.id,
    rp.id,
    1,
    (SELECT id FROM mes.operacion WHERE codigo = 'TENIDO'),
    pt.maquina::int,
    p.receta_id,
    NULL,
    rp.fyh_cre
FROM public.produccion_tenido pt
JOIN public.partida p  ON p.id = pt.partida_id
JOIN mes.partida rp
    ON  rp.partida_origen_id = pt.partida_id
    AND rp.fyh_cre = ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
WHERE pt.tipo != 'Teñido'
  AND pt.partida_id IN (SELECT id FROM mes.partida)
ON CONFLICT DO NOTHING;

-- partida_detalle for rework partidas — adjusted target: only the reprocessed roll count (SAP PP/PPI split model).
INSERT INTO mes.partida_detalle (partida_id, item_id, cantidad, unidad_id, usr_cre, fyh_cre)
SELECT
    rp.id,
    ird.item_id,
    COALESCE(pt.rollos, 0),
    (SELECT id FROM unidad WHERE codigo = 'UN'),
    NULL,
    rp.fyh_cre
FROM public.produccion_tenido pt
JOIN mes.partida rp
    ON  rp.partida_origen_id = pt.partida_id
    AND rp.fyh_cre = ((pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
JOIN public.partida p ON p.id = pt.partida_id
JOIN item_rollo_detalle ird ON ird.articulo_id = p.articulo_id AND ird.flg_rib = false
WHERE pt.tipo != 'Teñido'
  AND pt.partida_id IN (SELECT id FROM mes.partida)
  AND COALESCE(pt.rollos, 0) > 0
ON CONFLICT DO NOTHING;

SELECT setval(pg_get_serial_sequence('mes.partida',      'id'), (SELECT MAX(id) FROM mes.partida));
SELECT setval(pg_get_serial_sequence('mes.partida_paso', 'id'), (SELECT MAX(id) FROM mes.partida_paso));

-- ============================================================================
-- COMPACTADO operacion — run on live DB if 07 migration already executed
-- ============================================================================
INSERT INTO mes.operacion (codigo, nombre, requiere_receta)
VALUES ('COMPACTADO', 'Compactado', false)
ON CONFLICT (codigo) DO NOTHING;

-- Billing-only operation: never assigned to an partida_paso.
-- Generates a separate invoice line when partida.flg_antipilling = true.
-- Rate maintained as a client-level wildcard row in doc.catalogo_precios.
INSERT INTO mes.operacion (codigo, nombre, requiere_receta)
VALUES ('ANTIPILLING', 'Antipilling', false)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================================
-- MIGRAR LOTES Y MOVIMIENTOS INICIALES DE INSUMOS
-- ============================================================================
-- SELECT DISTINCT motivo FROM entrada_inventario
---TIPOS DE ENTRADA
--reconteo --NECEISTO DOCUMENTO (si es cuadre) joinear por fecha y hora
--compra --NECESITA DOCUMENTO
--ajuste
---TIPOS DE SALIDA
-- otros
-- desmontado
-- lavado
-- matizado
-- mantenimiento
-- lavado maquina
-- receta
-- ajuste receta
-- ajuste
-- reconteo
----TODOS LOS CUADRES SON RECONTEO, pero no todos los reconteos son cuadres
    -- SELECT ei.* FROM entrada_inventario ei
    -- JOIN cuadre_inventario ci ON ei.fyh_solicitud_tz = ci.fecha_cierre;
    -- SELECT si.* FROM salida_inventario si
    -- JOIN cuadre_inventario ci ON si.fyh_solicitud_tz = ci.fecha_cierre

--COMRPAS con mas de una guia de remision/ingreso
-- SELECT c.id FROM compra LEFT JOIN 
-- WITH ec as(SELECT DISTINCT ei.id entrada_inventario_id,ci.compra_id FROM entrada_inventario ei
-- JOIN entrada_inventario_detalle eid ON ei.id=eid.entrada_inventario_id
-- JOIN compra_x_insumo ci ON ci.id=eid.compra_x_insumo_id
-- ), repetidas as(
--     SELECT ec.compra_id, COUNT(*) AS cantidad
--     FROM ec
--     GROUP BY 1
--     HAVING COUNT(*) > 1
-- )SELECT guia_remision FROM compra WHERE id IN (SELECT compra_id FROM repetidas)
----NOTA, terminar de migrar entradas, diseño
---1. lotes ---primero lotes con mismo id de inventario, luego updatear los ids de documento
---2.guias
---3. movimientos
---LUEGO RECIEN SALIDAS

INSERT INTO inventario.lote(
    id,item_id,cantidad,usr_cre,fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    i.id,
    COALESCE(ip.insumo_id, i.insumo_id)  AS item_id,
    i.cantidad,
    i.usr_cre,
    i.fyh_cre
FROM inventario i
LEFT JOIN insumo_x_proveedor         ip  ON ip.id  = i.insumo_x_proveedor_id
WHERE i.cantidad > 0.00
  AND COALESCE(ip.insumo_id, i.insumo_id) IS NOT NULL;


SELECT setval(
    pg_get_serial_sequence('inventario.lote', 'id'),
    (SELECT MAX(id) FROM inventario.lote)
);


-- ============================================================================
-- SEED ITEM_VALORACION  →  inventario.item_valoracion
-- ============================================================================
-- Source: public.inventario (ingress ledger — cantidad = original ingress qty, never decremented)
--   precio_promedio : WAC of ingress lots using cost at ingress time, priority:
--                     1. inventario.costo_bruto_kg  (recorded at receipt)
--                     2. insumo_x_proveedor.precio_x_kg_usd  (supplier price)
--                     3. insumo.precio_prom_kg_usd  (catalog fallback)
--                     Weighted by cantidad so larger lots have proportional influence.
--   stock_qty       : SUM of all ingress quantities per item (matches migrated lote sum)
--   stock_valorado  : precio_promedio × stock_qty
-- Items with no resolvable cost across all three sources are excluded.
-- WAC trigger (fn_trg_actualizar_map) is bypassed here — movements have NULL
-- precio_unitario. Going forward the trigger handles new COMPRA_ING movements.
-- ============================================================================
INSERT INTO inventario.item_valoracion (item_id, precio_promedio, stock_qty, stock_valorado, fyh_mod)
SELECT it.id,
       SUM(COALESCE(i.costo_bruto_kg, ixp.precio_x_kg_usd,ins.precio_prom_kg_usd) * i.cantidad) / NULLIF(SUM(i.cantidad), 0),
       SUM(i.cantidad),
       SUM(COALESCE(i.costo_bruto_kg, ixp.precio_x_kg_usd,ins.precio_prom_kg_usd) * i.cantidad),
       NOW()
FROM inventario i
LEFT JOIN insumo_x_proveedor ixp ON ixp.id = i.insumo_x_proveedor_id
JOIN item it ON it.id = COALESCE(ixp.insumo_id, i.insumo_id)
LEFT JOIN insumo ins ON ins.id = COALESCE(ixp.insumo_id, i.insumo_id)
WHERE COALESCE(i.costo_bruto_kg, ixp.precio_x_kg_usd,ins.precio_prom_kg_usd) IS NOT NULL
GROUP BY it.id
ON CONFLICT (item_id) DO UPDATE
    SET precio_promedio = EXCLUDED.precio_promedio,
        stock_qty       = EXCLUDED.stock_qty,
        stock_valorado  = EXCLUDED.stock_valorado,
        fyh_mod         = EXCLUDED.fyh_mod;

-- ============================================================================
-- mes.tiempos_estandar_tenido  ←  public.tiempos_estandar_tenido
-- tipo_receta_id dropped (was used inconsistently across legacy functions).
-- adicional_id replaced by flg_antipilling boolean.
-- DISTINCT ON new key resolves any duplicates that tipo_receta_id created.
-- ============================================================================

-- SELECT * FROM inventario.lote WHERE id NOT IN (SELECT id FROM inventario)

-- WITH 
-- ec as(
--     SELECT  DISTINCT inv.id inventario_id,eid.entrada_inventario_id,ci.compra_id,inv.insumo_x_proveedor_id,inv.cantidad FROM entrada_inventario ei
--     JOIN entrada_inventario_detalle eid ON ei.id=eid.entrada_inventario_id
--     JOIN compra_x_insumo ci ON ci.id=eid.compra_x_insumo_id
--     JOIN inventario inv ON inv.entrada_inventario_detalle_id = eid.id
-- )SELECT COUNT(*) FROM ec;

-- ============================================================================
-- MIGRAR COMPRAS
-- ============================================================================
-- Must run BEFORE the guia block below: doc.compra_guia_remision has FK → doc.compra(id)
-- and the guia block already inserts into doc.compra_guia_remision using public.compra.id
-- values, so doc.compra must exist with preserved IDs first.
--
-- Legacy shape (public schema):
--   compra            → header with factura text, guia_remision text, payment all-in-one
--   compra_x_insumo   → line items (insumo_id, cantidad, precio_x_kg_usd)
--   letra_compra      → payment letters tied to compra_id
--
-- New shape (doc schema):
--   factura_proveedor → split out from compra; letras now hang off factura, not compra
--   compra            → lightweight header; linked to facturas via doc.compra_factura_proveedor junction
--   compra_detalle    → line items; insumo_id resolved → item_id directly (item.id = insumo.id)
--   compra_guia_remision → junction written by the guia block below; no action needed here
--   letra             → re-linked from compra → factura_proveedor chain
-- ============================================================================

-- Step 1: doc.factura_proveedor
-- Sourced from public.compra rows that have a parseable 'SERIE-CORRELATIVO' factura.
-- subtotal/igv breakdown is not available in legacy data; total carries the full amount.
-- Rows with missing or malformed factura are skipped (no compra_factura_proveedor row created for them).
-- Run the orphan check query below before go-live to assess the gap.
INSERT INTO doc.factura_proveedor (
    tercero_id,
    serie,
    numero,
    fecha_emision,
    fecha_vencimiento,
    tipo_pago,
    moneda,
    tipo_cambio,
    subtotal,
    igv,
    total,
    estado_pago,
    observacion,
    usr_cre,
    fyh_cre
)
SELECT DISTINCT ON (c.proveedor_id, SPLIT_PART(c.factura, '-', 1), NULLIF(regexp_replace(SPLIT_PART(c.factura, '-', 2), '[^0-9].*$', ''), '')::INT)
    (SELECT id FROM tercero WHERE proveedor_id = c.proveedor_id),
    SPLIT_PART(c.factura, '-', 1)                                                          AS serie,
    NULLIF(regexp_replace(SPLIT_PART(c.factura, '-', 2), '[^0-9].*$', ''), '')::INT       AS numero,
    COALESCE(c.fecha_giro, c.fecha_remision, c.fyh_cre_tz::DATE)                          AS fecha_emision,
    c.fecha_vencimiento,
    c.tipo_pago,
    'USD'::CHAR(3),
    NULL                                                                                   AS tipo_cambio,
    c.total_usd    AS subtotal,   -- no legacy breakdown; subtotal = total satisfies CHECK
    0              AS igv,
    c.total_usd    AS total,
    COALESCE(c.estado_pago, 'pendiente')                                                   AS estado_pago,
    NULL                                                                                   AS observacion,
    CASE WHEN c.usr_cre NOT IN ('authenticated', 'anon', 'postgres') THEN c.usr_cre::INT ELSE NULL END,
    c.fyh_cre_tz
FROM public.compra c
WHERE c.factura IS NOT NULL
  AND c.factura LIKE '%-%'
  AND c.proveedor_id IS NOT NULL
  AND NULLIF(regexp_replace(SPLIT_PART(c.factura, '-', 2), '[^0-9].*$', ''), '') IS NOT NULL
  AND c.total_usd > 0
ORDER BY c.proveedor_id, SPLIT_PART(c.factura, '-', 1), NULLIF(regexp_replace(SPLIT_PART(c.factura, '-', 2), '[^0-9].*$', ''), '')::INT, c.fyh_cre_tz DESC;

-- Orphan check: compras with a factura that couldn't be parsed → no factura_proveedor created
-- SELECT id, factura FROM public.compra WHERE factura IS NOT NULL AND factura NOT LIKE '%-%';


-- Step 2: doc.compra  (OVERRIDING SYSTEM VALUE preserves public.compra.id for FK compatibility)
INSERT INTO doc.compra (
    id,
    tercero_id,
    fecha,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    c.id,
    (SELECT id FROM tercero WHERE proveedor_id = c.proveedor_id),
    COALESCE(c.fecha_remision, c.fyh_cre_tz::DATE) AS fecha,
    CASE WHEN c.usr_cre NOT IN ('authenticated', 'anon', 'postgres') THEN c.usr_cre::INT ELSE NULL END,
    c.fyh_cre_tz
FROM public.compra c
WHERE c.proveedor_id IS NOT NULL;

-- Step 2b: doc.compra_factura_proveedor — link each compra to its factura (where parseable)
INSERT INTO doc.compra_factura_proveedor (compra_id, factura_proveedor_id, fyh_cre)
SELECT
    c.id,
    fp.id,
    c.fyh_cre_tz
FROM public.compra c
JOIN doc.factura_proveedor fp
    ON  fp.tercero_id = (SELECT id FROM tercero WHERE proveedor_id = c.proveedor_id)
    AND fp.serie      = SPLIT_PART(c.factura, '-', 1)
    AND fp.numero     = NULLIF(regexp_replace(SPLIT_PART(c.factura, '-', 2), '[^0-9].*$', ''), '')::INT
WHERE c.proveedor_id IS NOT NULL
  AND c.factura IS NOT NULL
ON CONFLICT DO NOTHING;

SELECT setval(
    pg_get_serial_sequence('doc.compra', 'id'),
    (SELECT MAX(id) FROM doc.compra)
);


-- Step 3: doc.compra_detalle  (from public.compra_x_insumo)
-- insumo_id → item_id resolved directly (item.id = insumo.id; OVERRIDING SYSTEM VALUE preserved IDs).
-- Rows where insumo_id has no match in item are silently dropped; run the gap check below first.
INSERT INTO doc.compra_detalle (
    compra_id,
    item_id,
    cantidad,
    precio_unitario,
    fyh_cre
)
SELECT
    cxi.compra_id,
    it.id,
    cxi.cantidad,
    cxi.precio_x_kg_usd,
    NOW()
FROM public.compra_x_insumo cxi
JOIN item it ON it.id = cxi.insumo_id
WHERE cxi.compra_id IN (SELECT id FROM doc.compra);

-- Gap check: line items whose insumo_id didn't resolve to any item
-- SELECT cxi.compra_id, cxi.insumo_id
-- FROM public.compra_x_insumo cxi
-- LEFT JOIN item it ON it.id = cxi.insumo_id
-- WHERE it.id IS NULL;


-- Step 4: doc.letra + doc.letra_factura  (from public.letra_compra)
-- New model: letra is a standalone payment instrument (tercero_id from proveedor).
-- Clearing to factura_proveedor is done via letra_factura junction.
-- IDs preserved (OVERRIDING SYSTEM VALUE) so letra.id = letra_compra.id — no temp
-- table or ROW_NUMBER correlation needed; clearing INSERT joins directly on lc.id.
-- Letras on compras with no linked factura_proveedor get a letra row but no clearing line.
INSERT INTO doc.letra (id, tercero_id, numero, monto, fecha_giro, fecha_vencimiento,
                       estado, fecha_pago, observacion, fyh_cre)
OVERRIDING SYSTEM VALUE
SELECT
    lc.id,
    dc.tercero_id,
    lc.numero_letra,
    lc.monto_usd,
    lc.fecha_emision,
    lc.fecha_vencimiento,
    CASE lc.estado
        WHEN 'emitida'    THEN 'emitida'::letra_estado_enum
        WHEN 'pagada'     THEN 'pagada'::letra_estado_enum
        WHEN 'vencida'    THEN 'vencida'::letra_estado_enum
        WHEN 'protestada' THEN 'protestada'::letra_estado_enum
        WHEN 'anulada'    THEN 'anulada'::letra_estado_enum
        ELSE                   'emitida'::letra_estado_enum
    END,
    lc.fecha_pago,
    lc.observaciones,
    COALESCE(lc.fyh_cre_tz, lc.fyh_cre::TIMESTAMPTZ)
FROM public.letra_compra lc
JOIN doc.compra dc ON dc.id = lc.compra_id;

SELECT setval(
    pg_get_serial_sequence('doc.letra', 'id'),
    (SELECT MAX(id) FROM doc.letra)
);

-- Clearing: one letra_factura row per letra where a factura_proveedor was linked
INSERT INTO doc.letra_factura (letra_id, factura_proveedor_id, monto_aplicado, fyh_cre)
SELECT
    lc.id,
    cfp.factura_proveedor_id,
    lc.monto_usd,
    NOW()
FROM public.letra_compra lc
JOIN doc.compra_factura_proveedor cfp ON cfp.compra_id = lc.compra_id
ON CONFLICT (letra_id, factura_proveedor_id) DO NOTHING;

-- Unmigrated letras: compras that had no parseable factura → no clearing line created
-- SELECT lc.id, lc.compra_id, lc.numero_letra, lc.monto_usd
-- FROM public.letra_compra lc
-- LEFT JOIN doc.compra_factura_proveedor cfp ON cfp.compra_id = lc.compra_id
-- WHERE cfp.factura_proveedor_id IS NULL;

-- ============================================================================

----CONFIGURAR GUIAS y
-- TRUNCATE TABLE doc.guia_remision_detalle,doc.guia_remision,doc.compra_guia_remision;
WITH 
ec as(
    SELECT  DISTINCT inv.id inventario_id,ci.compra_id,eid.entrada_inventario_id,inv.insumo_x_proveedor_id,inv.cantidad FROM entrada_inventario ei
    JOIN entrada_inventario_detalle eid ON ei.id=eid.entrada_inventario_id
    JOIN compra_x_insumo ci ON ci.id=eid.compra_x_insumo_id
    JOIN inventario inv ON inv.entrada_inventario_detalle_id = eid.id
)
, inv as(
    SELECT 
    DENSE_RANK() OVER (PARTITION BY compra_id ORDER BY entrada_inventario_id) AS rw,
        * 
        FROM ec
)
,
compra_data AS (
    SELECT 
        inv.*,
        c.guia_remision,
        c.proveedor_id,  -- adjust column name as needed
        c.fecha_remision,         -- adjust column name as needed
        c.fyh_cre + INTERVAL '5 hours' fyh_cre,
        CASE WHEN c.usr_cre NOT IN ('authenticated', 'anon', 'postgres') THEN c.usr_cre::INT ELSE NULL END AS usr_cre,
        SPLIT_PART(c.guia_remision, '-', 1) AS serie, -- serie is always the prefix before '-'
        CASE 
            WHEN inv.rw = 1 THEN SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1)
            ELSE SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1) || '-' || inv.rw::text
        END AS correlativo
    FROM inv
    JOIN compra c ON c.id = inv.compra_id
),
inserted_guias AS (
    INSERT INTO doc.guia_remision (
        guia_remision_tipo_id, tercero_id, serie, correlativo, fecha_emision, usr_cre, fyh_cre
    )
    SELECT
        (SELECT id FROM doc.guia_remision_tipo WHERE codigo = 'COMPRA_INGRESO'),
        (SELECT id FROM tercero WHERE proveedor_id = cd.proveedor_id),
        serie,
        correlativo,
        MAX(fecha_remision::date)::TIMESTAMP + INTERVAL '5 hours' AS fecha_emision,
        MAX(usr_cre)              AS usr_cre,
        MAX(fyh_cre)              AS fyh_cre
    FROM compra_data cd
    -- GROUP BY unique key only: same (tipo,tercero,serie,correlativo) from multiple lotes → one guia.
    -- UNIQUE constraint is (tercero_id, serie, correlativo, guia_remision_tipo_id) — see 07_new_tables.
    GROUP BY 1,2,3,4
    RETURNING id, serie, correlativo
),inserted_compra_guias_remision AS (
    INSERT INTO doc.compra_guia_remision(guia_remision_id,compra_id)
    SELECT i.id, c.compra_id FROM inserted_guias i JOIN compra_data c ON i.serie = c.serie AND i.correlativo = c.correlativo
    GROUP BY 1,2
)
UPDATE inventario.lote 
SET documento_tipo = 'GUIA_REMISION',
documento_id = i.id
FROM compra_data c 
JOIN inserted_guias i ON i.serie = c.serie AND i.correlativo = c.correlativo
WHERE c.inventario_id = inventario.lote.id;

INSERT INTO doc.guia_remision_detalle(
guia_remision_id, item_id, cantidad
)
SELECT doc.guia_remision.id, l.item_id, l.cantidad
FROM inventario.lote l
JOIN doc.guia_remision ON doc.guia_remision.id = l.documento_id AND l.documento_tipo='GUIA_REMISION';

SELECT setval(pg_get_serial_sequence('doc.guia_remision',        'id'), (SELECT MAX(id) FROM doc.guia_remision));
SELECT setval(pg_get_serial_sequence('doc.guia_remision_detalle','id'), (SELECT MAX(id) FROM doc.guia_remision_detalle));


-- WITH
-- ec as(
--     SELECT  DISTINCT inv.id inventario_id,ci.compra_id,eid.entrada_inventario_id,inv.insumo_x_proveedor_id,inv.cantidad FROM entrada_inventario ei
--     JOIN entrada_inventario_detalle eid ON ei.id=eid.entrada_inventario_id
--     JOIN compra_x_insumo ci ON ci.id=eid.compra_x_insumo_id
--     JOIN inventario inv ON inv.entrada_inventario_detalle_id = eid.id
-- )
-- , inv as(
--     SELECT 
--     DENSE_RANK() OVER (PARTITION BY compra_id ORDER BY entrada_inventario_id) AS rw,
--         * 
--         FROM ec
-- )
-- ,
-- compra_data AS (
--     SELECT 
--         inv.*,
--         c.guia_remision,
--         c.proveedor_id,  -- adjust column name as needed
--         c.fecha_remision,         -- adjust column name as needed
--         c.fyh_cre + INTERVAL '5 hours' fyh_cre,
--         c.usr_cre,
--         CASE 
--             WHEN inv.rw = 1 THEN SPLIT_PART(c.guia_remision, '-', 1)
--             ELSE SPLIT_PART(c.guia_remision, '-', 1)  -- same serie?
--         END AS serie,
--         CASE 
--             WHEN inv.rw = 1 THEN SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1)
--             ELSE SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1) || '-' || inv.rw::text
--         END AS correlativo
--     FROM inv
--     JOIN compra c ON c.id = inv.compra_id
-- ),
-- inserted_guias AS (
--     INSERT INTO doc.guia_remision (
--         guia_remision_tipo_id, serie, correlativo, 
--         emisor_proveedor_id, fecha_emision, usr_cre, fyh_cre
--     )
--     SELECT 
--         (SELECT id FROM doc.guia_remision_tipo WHERE codigo = 'COMPRA_INGRESO'),
--         serie,
--         correlativo,
--         proveedor_id,
--         fecha_remision::date,
--         usr_cre,
--         fyh_cre
--     FROM compra_data
--     GROUP BY 1,2,3,4,5,6,7
--     RETURNING id, serie, correlativo
-- ),
-- inserted_detalles AS (
--     INSERT INTO doc.guia_remision_detalle (
--         guia_remision_id, item_id, cantidad, usr_cre, fyh_cre
--     )
--     SELECT 
--         inserted_guias.id,
--         ip.item_id,
--         i.cantidad,
--         i.usr_cre,
--         i.fyh_cre
--     FROM compra_data c
--     JOIN insumo_x_proveedor ip ON ip.id = c.insumo_x_proveedor_id
--     JOIN inserted_guias ON inserted_guias.serie = c.serie AND inserted_guias.correlativo = c.correlativo
--     JOIN item ON item.id = ip.insumo_id
-- )
-- UPDATE inventario.lote 
-- SET tipo_documento = 'guia_remision',
-- documento_id = i.documento_id
-- FROM compra c 
-- JOIN inv ON inv.compra_id = c.id
-- WHERE c.inventario_id = inventario.lote.id;

-- ============================================================================
-- MIGRAR CUADRES DE INVENTARIO
-- ============================================================================
-- Source:  public.cuadre_inventario        → inventario.cuadre
--          public.cuadre_inventario_detalle → inventario.cuadre_detalle
--
-- Key mapping:
--   cuadre_inventario.estado ('borrador'|'preparado'|'ejecutado') stays the same
--   cuadre_inventario_detalle.insumo_id → item_id directly (item.id = insumo.id)
--   costo_bruto_prom_kg_sistema → precio_promedio_sistema
--   costo_bruto_total_sistema   → stock_valorado_sistema
--
-- Must run BEFORE the lote tagging UPDATE below, because that UPDATE sets
-- inventario.lote.documento_id to the cuadre id — the new cuadre rows must
-- exist first so the FK is valid.
-- ============================================================================

-- Step 1: inventario.cuadre (OVERRIDING SYSTEM VALUE preserves IDs used by lotes)
INSERT INTO inventario.cuadre (
    id,
    fecha_cuadre,
    fecha_cierre,
    estado,
    usr_cre,
    fyh_cre,
    usr_mod,
    fyh_mod
)
OVERRIDING SYSTEM VALUE
SELECT
    ci.id,
    ci.fecha_cuadre,
    ci.fecha_cierre,
    ci.estado::text::inventario.cuadre_estado_enum,
    ci.usr_cre,
    ci.fyh_cre,
    ci.usr_mod,
    ci.fyh_mod
FROM public.cuadre_inventario ci;

SELECT setval(
    pg_get_serial_sequence('inventario.cuadre', 'id'),
    (SELECT MAX(id) FROM inventario.cuadre)
);

-- Step 2: inventario.cuadre_detalle
-- insumo_id → item_id resolved directly (item.id = insumo.id; OVERRIDING SYSTEM VALUE preserved IDs).
-- Rows whose insumo_id cannot be resolved are skipped; run gap check below.
INSERT INTO inventario.cuadre_detalle (
    cuadre_id,
    item_id,
    cantidad_sistema,
    precio_promedio_sistema,
    stock_valorado_sistema,
    ult_precio_compra,
    cantidad_contada,
    usr_mod,
    fyh_mod
)
SELECT
    cid.cuadre_inventario_id,
    it.id,
    cid.cantidad_sistema,
    cid.costo_bruto_prom_kg_sistema,
    cid.costo_bruto_total_sistema,
    cid.ult_precio_compra,
    cid.cantidad_contada,
    cid.usr_mod,
    cid.fyh_mod
FROM public.cuadre_inventario_detalle cid
JOIN item it ON it.id = cid.insumo_id
WHERE cid.cuadre_inventario_id IN (SELECT id FROM inventario.cuadre);

-- Gap check: detalle rows whose insumo didn't resolve
-- SELECT cid.cuadre_inventario_id, cid.insumo_id
-- FROM public.cuadre_inventario_detalle cid
-- LEFT JOIN item it ON it.id = cid.insumo_id
-- WHERE it.id IS NULL;

-- ============================================================================
-- TAG CUADRE-SOURCED LOTES  →  inventario.lote (UPDATE)
-- ============================================================================
-- Scope:   Insumo lotes whose legacy entrada_inventario had motivo ∈ (ajuste, reconteo)
--          and whose timestamp matches a cuadre.fecha_cierre.
-- Effect:  Sets documento_tipo = 'CUADRE', documento_id = cuadre.id on those lotes,
--          overwriting the NULL originally set during the insumo lote INSERT.
-- Must run BEFORE the INSUMO INGRESS MOVEMENTS block so the lote.documento_tipo
-- values read there are already correct.
-- ============================================================================
UPDATE inventario.lote
SET documento_tipo = 'CUADRE',
    documento_id   = ci.id
FROM public.inventario i                                          -- legacy stock table (public schema)
JOIN public.entrada_inventario_detalle eid ON i.entrada_inventario_detalle_id = eid.id
JOIN public.entrada_inventario         ei  ON ei.id = eid.entrada_inventario_id
JOIN inventario.cuadre                 ci  ON ci.fecha_cierre = ei.fyh_solicitud_tz
WHERE ei.motivo IN ('ajuste', 'reconteo')
  AND inventario.lote.id = i.id;


----PENDIENTE LIMPIAR id de documento de movimientos que NO son de cuadres
-- SELECT l.*,i.*
-- FROM inventario.lote l
-- JOIN public.inventario i ON i.id=l.id
-- JOIN public.entrada_inventario_detalle eid ON i.entrada_inventario_detalle_id=eid.id
-- JOIN public.entrada_inventario ei ON ei.id=eid.entrada_inventario_id
-- LEFT JOIN inventario.cuadre ci ON ci.fecha_cierre = ei.fyh_solicitud_tz
-- WHERE ei.motivo IN ('ajuste','reconteo') AND ci.id IS NOT NULL

-- ============================================================================
-- INSUMO INGRESS MOVEMENTS  →  inventario.item_movimientos
-- ============================================================================
-- Source:  inventario.lote  (already migrated from public.inventario + public.compra)
--          joined to public.entrada_inventario via public.inventario to recover motivo.
-- Scope:   All insumo lotes with cantidad > 0.  Excludes roll lotes (those are in the
--          BACKFILL ROLL LOTES section below and have documento_tipo = 'PARTIDA').
--
-- Movement type mapping:
--   lote.documento_tipo = 'GUIA_REMISION'  → COMPRA_ING  (purchase arrival)
--   lote.documento_tipo = 'CUADRE'         → AJUSTE_POS  (positive adjustment from count)
--   entrada_inventario.motivo = 'muestra'  → MUESTRA_ING (non-valorizable sample receipt)
--   anything else (orphan/manual entries)  → AJUSTE_POS  (safe fallback)
--
-- doc_movimiento_id grouping:
--   One posting document per distinct (documento_tipo, documento_id) pair — i.e. one
--   per guia_remision or per cuadre.  Muestra events group by entrada_inventario.id.
--   nextval fires inside the inner DISTINCT subquery so each group gets exactly one seq.
-- ============================================================================
WITH lote_source AS (
    -- Enrich each lote with its legacy entrada motivo for movement type + grouping.
    -- Muestra lotes have documento_tipo = NULL on the lote; we use entrada_inventario.id
    -- as the grouping key so each muestra event gets its own doc_movimiento_id.
    SELECT
        i.id, i.item_id, i.cantidad, i.documento_tipo, i.documento_id, i.usr_cre, i.fyh_cre,
        ei.motivo,
        -- Effective grouping key: lote's own doc for known types, entrada id for muestra
        COALESCE(i.documento_tipo, CASE WHEN ei.motivo = 'muestra' THEN 'MUESTRA' END) AS grp_tipo,
        COALESCE(i.documento_id,   CASE WHEN ei.motivo = 'muestra' THEN ei.id      END) AS grp_id
    FROM inventario.lote i
    LEFT JOIN public.inventario                inv ON inv.id  = i.id
    LEFT JOIN public.entrada_inventario_detalle eid ON eid.id = inv.entrada_inventario_detalle_id
    LEFT JOIN public.entrada_inventario         ei  ON ei.id  = eid.entrada_inventario_id
    WHERE i.cantidad > 0
),
doc_posting AS (
    -- One doc_movimiento_id per distinct grouping key
    -- DISTINCT in subquery so nextval fires once per unique group, not per row
    SELECT grp_tipo, grp_id, nextval('inventario.mov_doc_seq') AS doc_movimiento_id
    FROM (
        SELECT DISTINCT grp_tipo, grp_id
        FROM lote_source
    ) t
)
INSERT INTO inventario.item_movimientos(
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id, destino_ubicacion_id, cantidad, documento_tipo, documento_id, observacion, usr_cre, fyh_cre, fecha_hora
)
SELECT
    dp.doc_movimiento_id,
    ls.item_id,
    ls.id,
    CASE ls.documento_tipo
        WHEN 'GUIA_REMISION' THEN (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'COMPRA_ING')
        WHEN 'CUADRE'        THEN (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS')
        ELSE CASE ls.motivo
            WHEN 'muestra' THEN (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'MUESTRA_ING')
            ELSE                (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS')
        END
    END,
    (SELECT inventario.ubicacion.id FROM inventario.ubicacion JOIN inventario.almacen ON inventario.almacen.id = inventario.ubicacion.almacen_id WHERE inventario.almacen.codigo = 'ALM_INS'),
    ls.cantidad,
    ls.documento_tipo,
    ls.documento_id,
    'Migración Inicial',
    ls.usr_cre,
    ls.fyh_cre,
    ls.fyh_cre
FROM lote_source ls
JOIN doc_posting dp
  ON dp.grp_tipo IS NOT DISTINCT FROM ls.grp_tipo
 AND dp.grp_id   IS NOT DISTINCT FROM ls.grp_id;
-- ============================================================================
-- INSUMO EGRESS MOVEMENTS  →  inventario.item_movimientos
-- ============================================================================
-- Source:  public.salida_inventario (header)
--          → public.salida_inventario_detalle (line items)
--          → public.salida_inventario_detalle_x_stock (actual per-lote consumption)
-- Scope:   Only salidas with estado = 'aprobado' (pending/cancelled never executed).
--          Excludes roll-lote consumptions — those are handled in BACKFILL ROLL LOTES.
--
-- Movement type mapping via motivo_map:
--   receta / matizado / lavado / lavado maquina / desmontado / ajuste receta → PROD_CONSUMO
--   ajuste / reconteo / merma / mantenimiento / otros                        → AJUSTE_NEG
--   muestra                                                                  → MUESTRA_EGR
--   transferencia: excluded — exists in the enum but no rows recorded with this motivo.
--   NULL motivo: excluded via WHERE below — rows without a motivo cannot be classified.
--
-- documento_tipo / documento_id on the movement:
--   CUADRE-linked:      salida matches a cuadre by timestamp AND motivo ∈ (ajuste, reconteo)
--                       → documento_tipo = 'CUADRE', documento_id = cuadre.id
--                       → doc_movimiento_id reused from that cuadre's ingress posting
--   PROD_CONSUMO + pxr: salida.partida_x_recetas_id IS NOT NULL
--                       → documento_tipo = 'partida_paso', documento_id = opp.id (actual partida_paso.id)
--                         (pxr.id mapped → opp.id via pxr_to_opp CTE; re-stamped to
--                          'partida_paso_ejecucion' by end-of-migration Step D)
--   all other:          documento_tipo / documento_id = NULL
-- ============================================================================
-- INSUMO EGRESS MOVEMENTS — SKIPPED (snapshot migration)
-- ============================================================================
-- This block was designed for full transaction-history migration. 

-- ============================================================================


WITH pxr_to_opp AS (
    -- Maps each partida_x_recetas row to the actual mes.partida_paso.id.
    -- pt.id was formerly used directly as opp_id (from the commented-out op_insert block
    -- where paso.id = pt.id). After schema redesign, paso IDs are auto-generated and
    -- pt.id = mes.partida.id, so we must JOIN through partida_paso to get the real paso id.
    -- secuencia = 1 targets the primary (TENIDO) paso — chemicals consumed at that step.
    SELECT DISTINCT ON (pxr.id)
        pxr.id AS pxr_id,
        opp.id AS opp_id
    FROM partida_x_recetas pxr
    JOIN produccion_tenido pt
        ON pt.partida_id   = pxr.partida_id
       AND pt.maquina::int = pxr.maquina_id
    JOIN mes.partida_paso opp ON opp.id = pt.id
    WHERE pxr.receta_id IS NOT NULL AND pxr.flg_elm = false
    ORDER BY pxr.id, ABS(pt.fecha::date - pxr.fecha::date)
),
motivo_map (motivo, codigo) AS (
    VALUES
        ('receta',        'PROD_CONSUMO'),
        ('matizado',      'PROD_CONSUMO'),
        ('lavado',        'PROD_CONSUMO'),
        ('lavado maquina','PROD_CONSUMO'),
        ('desmontado',    'PROD_CONSUMO'),
        ('ajuste receta', 'PROD_CONSUMO'),
        ('ajuste',        'AJUSTE_NEG'),
        ('reconteo',      'AJUSTE_NEG'),
        ('merma',         'AJUSTE_NEG'),
        ('muestra',       'MUESTRA_EGR'),
        ('mantenimiento', 'AJUSTE_NEG'),
        ('otros',         'AJUSTE_NEG')
),
doc_posting AS (
    SELECT
        si.id AS salida_inventario_id,
        ci.id AS cuadre_id,
        COALESCE(
            (SELECT im.doc_movimiento_id
             FROM inventario.item_movimientos im
             WHERE im.documento_tipo = 'CUADRE' AND im.documento_id = ci.id
             LIMIT 1),
            nextval('inventario.mov_doc_seq')
        ) AS doc_movimiento_id
    FROM public.salida_inventario si
    LEFT JOIN inventario.cuadre ci
           ON ci.fecha_cierre = si.fyh_solicitud_tz
          AND si.motivo::text IN ('ajuste', 'reconteo')
    WHERE si.estado = 'aprobado'
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, cantidad, documento_tipo, documento_id,
    observacion, usr_cre, fyh_cre, fecha_hora
)
SELECT
    dp.doc_movimiento_id,
    l.item_id,
    sdxs.inventario_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = mm.codigo),
    (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_INS'),
    sdxs.cantidad,
    CASE
        WHEN dp.cuadre_id IS NOT NULL  THEN 'CUADRE'
        WHEN mm.codigo = 'PROD_CONSUMO' AND si.partida_x_recetas_id IS NOT NULL THEN 'partida_paso'
    END,
    CASE
        WHEN dp.cuadre_id IS NOT NULL  THEN dp.cuadre_id
        WHEN mm.codigo = 'PROD_CONSUMO' AND si.partida_x_recetas_id IS NOT NULL THEN pto.opp_id
    END,
    si.observacion,
    si.usr_solicita,
    COALESCE(si.fyh_salida_real, si.fyh_solicitud_tz),
    COALESCE(si.fyh_salida_real, si.fyh_solicitud_tz)
FROM public.salida_inventario si
JOIN public.salida_inventario_detalle sid ON sid.salida_inventario_id = si.id
JOIN public.salida_inventario_detalle_x_stock sdxs ON sdxs.salida_inventario_detalle_id = sid.id
JOIN inventario.lote l ON l.id = sdxs.inventario_id
JOIN motivo_map mm ON mm.motivo = si.motivo::text
JOIN doc_posting dp ON dp.salida_inventario_id = si.id
LEFT JOIN pxr_to_opp pto ON pto.pxr_id = si.partida_x_recetas_id
WHERE si.motivo IS NOT NULL
  AND sdxs.cantidad::numeric(12,4) > 0;  -- excludes sub-0.0001 quantities that truncate to 0

-- SELECT COUNT(*) FROM termofijado;
-- SELECT COUNT(*) FROM produccion_tenido;
-- SELECT COUNT(*) FROM compactado;
-- SELECT COUNT(*) FROM observado;
-- SELECT COUNT(*) FROM perchado;
-- SELECT * FROM termofijado LIMIT 5;
-- SELECT * FROM produccion_tenido LIMIT 5;
-- SELECT * FROM compactado LIMIT 5;
-- SELECT * FROM observado LIMIT 5;
-- SELECT * FROM perchado LIMIT 5;
-- SELECT codigo, nombre FROM mes.operacion ORDER BY id;
-- SELECT COUNT(*) FROM produccion_tenido pt
-- JOIN partida_x_recetas pxr ON pxr.partida_id = pt.partida_id
--     AND pxr.maquina_id::text = pt.maquina::text
-- WHERE pxr.flg_elm = false AND pxr.receta_id IS NOT NULL;
-- SELECT DISTINCT tipo FROM produccion_tenido ORDER BY 1;
-- SELECT DISTINCT maquina FROM produccion_tenido ORDER BY 1 LIMIT 20;

-- ============================================================================
-- BACKFILL ROLL LOTES (HISTÓRICO)
-- ============================================================================
-- No per-roll tracking existed in the legacy system. We reconstruct one lote
-- per physical roll from partida aggregate data.
--
-- Full movement lifecycle per roll:
--   Step 1  lote_insert      Create raw roll lote (flg_tenido=false), doc=PARTIDA
--   Step 2  opi_insert       Link lote → partida_componente (earliest NORMAL orden)
--   Step 3  oppi_insert      Link opi → partida_paso_item (secuencia=1)
--   Step 4  SERV_ING         Raw roll received from client → ALM_CRU, doc=PARTIDA
--   Step 5  PROD_CONSUMO     Raw roll consumed by paso → ALM_CRU, doc=partida_paso
--                            (only for rolls that got an oppi in step 3)
--   Step 6  SERV_EGR (ghost) Raw roll returned as-is for rolls that got an opi
--                            but no oppi (no paso link), doc=partida_paso
--   Step 7  PROD_ING         Dyed roll lote (flg_tenido=true) produced at fecha_entrega,
--                            doc=partida_paso
--                            (only for rolls with oppi; falls through if no dyed item exists)
--   Step 8  SERV_EGR         Dyed roll dispatched to client at fecha_entrega,
--                            doc=partida_paso
--
-- propietario_id:
--   legacy cliente.cliente started with 'MLR/' or 'OSWALDO/' → MLR (id=1)
--   otherwise → tercero.id (client owns the roll)
--   Note: prefix check done on public.cliente directly; tercero.cliente_id2 is NULL
--   when only the prefixed alias existed, so it is insufficient on its own.
-- ============================================================================

-- GAP AUDIT: expected roll count vs migrated lote count
-- Run before/after to verify parity. Known exclusion causes:
--   A) articulo_id has no item_rollo_detalle row (missing item mapping)
--   B) cliente_id has no tercero row (bridge gap)
--
-- Expected (legacy):
--   SELECT SUM(rollos)+SUM(rib) FROM public.partida
--   WHERE (rollos > 0 AND peso_rollos > 0) OR (rib > 0 AND peso_rib > 0)
-- Migrated:
--   SELECT COUNT(*) FROM inventario.lote WHERE documento_tipo = 'PARTIDA'
--
-- Exclusion cause A — partidas with no item_rollo_detalle match:
--   SELECT p.id, p.codigo, p.articulo_id, p.rollos, p.rib
--   FROM public.partida p
--   WHERE ((p.rollos > 0 AND p.peso_rollos > 0) OR (p.rib > 0 AND p.peso_rib > 0))
--     AND NOT EXISTS (SELECT 1 FROM item_rollo_detalle ird WHERE ird.articulo_id = p.articulo_id)
--   ORDER BY p.id;
--
-- Exclusion cause B — partidas with no tercero bridge match:
--   SELECT p.id, p.codigo, p.cliente_id, c.cliente
--   FROM public.partida p
--   JOIN public.cliente c ON c.id = p.cliente_id
--   WHERE ((p.rollos > 0 AND p.peso_rollos > 0) OR (p.rib > 0 AND p.peso_rib > 0))
--     AND NOT EXISTS (
--         SELECT 1 FROM tercero t
--         WHERE t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
--     )
--   ORDER BY p.id;
COMMIT;

SET statement_timeout = 0;

ALTER TABLE inventario.lote DISABLE TRIGGER trg_bi_lote_secuencia;
ALTER TABLE inventario.lote ALTER COLUMN secuencia DROP NOT NULL;

-- Steps 1–4 (single CTE chain — must run atomically)
-- 1. oppi — must go first (FK → opi)
-- DELETE FROM mes.partida_paso_item
-- WHERE partida_componente_id IN (
--     SELECT id FROM mes.partida_componente
--     WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA')
-- );

-- -- 2. opi
-- DELETE FROM mes.partida_componente
-- WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA');

-- -- 3. SERV_ING movements
-- DELETE FROM inventario.item_movimientos
-- WHERE documento_tipo = 'PARTIDA'
--   AND item_movimiento_tipo_id = (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING');
-- -- 4. roll lotes
-- ALTER TABLE inventario.lote DISABLE TRIGGER USER;
-- DELETE FROM inventario.lote WHERE documento_tipo = 'PARTIDA';
-- ALTER TABLE inventario.lote ENABLE TRIGGER USER;


-- Step 4: SERV_ING

-- ============================================================================
-- RERUN SNIPPET — Steps 2–3 only (opi + oppi reassignment)
WITH roll_source AS (
    -- Regular rolls — rn = position within partida (1..rollos)
    SELECT
        p.id          AS partida_id,
        ird.item_id,
        p.peso_rollos / NULLIF(p.rollos, 0)  AS cantidad,
        CASE WHEN c.cliente ILIKE 'MLR/%' OR c.cliente ILIKE 'OSWALDO/%' THEN 1 ELSE t.id END AS propietario_id,
        p.fyh_cre_tz  AS fyh_cre,
        p.usr_cre,
        false         AS flg_rib,
        gs.n          AS rn
    FROM public.partida p
    JOIN public.cliente c ON c.id = p.cliente_id
    JOIN item_rollo_detalle ird
        ON ird.articulo_id = p.articulo_id AND ird.flg_rib = false
    JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
    CROSS JOIN generate_series(1, GREATEST(p.rollos, 0)) gs(n)
    WHERE p.rollos > 0 AND p.peso_rollos > 0

    UNION ALL

    -- Rib rolls — rn = position within partida (1..rib)
    SELECT
        p.id          AS partida_id,
        ird.item_id,
        p.peso_rib / NULLIF(p.rib, 0)        AS cantidad,
        CASE WHEN c.cliente ILIKE 'MLR/%' OR c.cliente ILIKE 'OSWALDO/%' THEN 1 ELSE t.id END AS propietario_id,
        p.fyh_cre_tz  AS fyh_cre,
        p.usr_cre,
        true          AS flg_rib,
        gs.n          AS rn
    FROM public.partida p
    JOIN public.cliente c ON c.id = p.cliente_id
    JOIN item_rollo_detalle ird
        ON ird.articulo_id = p.articulo_id AND ird.flg_rib = true
    JOIN tercero t ON t.cliente_id = p.cliente_id OR t.cliente_id2 = p.cliente_id
    CROSS JOIN generate_series(1, GREATEST(p.rib, 0)) gs(n)
    WHERE p.rib > 0 AND p.peso_rib > 0
),
ingress_posting AS (
    -- One doc_movimiento_id per partida — DISTINCT in subquery before nextval fires
    SELECT partida_id, nextval('inventario.mov_doc_seq') AS doc_movimiento_id
    FROM (SELECT DISTINCT partida_id FROM roll_source) t
),
lote_insert AS ( -- Step 1: raw roll lotes — inserted ordered by (partida_id, flg_rib, rn)
    -- so that lote IDs are assigned in roll_source order, allowing rn re-derivation below
    INSERT INTO inventario.lote (item_id, cantidad, documento_tipo, documento_id, propietario_id, usr_cre, fyh_cre)
    SELECT item_id, cantidad, 'PARTIDA', partida_id, propietario_id, usr_cre, fyh_cre
    FROM (SELECT * FROM roll_source ORDER BY partida_id, flg_rib, rn) rs
    RETURNING id AS lote_id, item_id, documento_id AS partida_id, cantidad, propietario_id, usr_cre, fyh_cre
),
lote_with_rn AS (
    -- Re-derive rn from lote_id order (matches insertion order above).
    -- flg_rib recovered via item_rollo_detalle.
    SELECT
        li.*,
        ird.flg_rib,
        ROW_NUMBER() OVER (PARTITION BY li.partida_id, ird.flg_rib ORDER BY li.lote_id) AS rn
    FROM lote_insert li
    JOIN item_rollo_detalle ird ON ird.item_id = li.item_id
),
pt_ranges AS (
    -- Roll ranges per pt row (= per op), using pt.rollos directly.
    -- NORMAL runs: cumulative sequential offset across runs ordered by fecha.
    -- REPROCESO runs: always start at roll 1 (re-process a subset of the same rolls).
    -- Only includes pt rows that produced a completed paso (EN partida excluded).
    SELECT
        pt.id                                                                           AS op_id,
        pt.partida_id,
        COALESCE(pt.rollos, 0)                                                          AS rollos,
        CASE WHEN pt.tipo = 'Teñido'
             THEN COALESCE(SUM(COALESCE(pt.rollos, 0)) OVER (
                      PARTITION BY pt.partida_id
                      ORDER BY pt.fecha, pt.id
                      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                  ), 0)
             ELSE 0
        END                                                                             AS rollos_start
    FROM produccion_tenido pt
    JOIN mes.partida_paso opp ON opp.id = pt.id  -- completed runs only (paso.id = pt.id via OVERRIDING)
),
opi_insert AS ( -- Step 2: assign each lote to the op(s) whose roll range covers its rn
    -- NORMAL: each roll falls into exactly one run (sequential ranges, no overlap).
    -- REPROCESO: overlaps from roll 1 — a roll may link to multiple REPROCESO ops.
    -- Rolls outside all ranges (pt.rollos sum < partida.rollos) get no opi;
    -- ghost Step 6 will close their inventory balance with a SERV_EGR.
    -- TODO: add rib support when pt gains a rib column (currently only regular rolls assigned).
    INSERT INTO mes.partida_componente (partida_id, lote_id, usr_cre, fyh_cre)
    SELECT
        pr.partida_id,
        lwr.lote_id,
        lwr.usr_cre,
        lwr.fyh_cre
    FROM lote_with_rn lwr
    JOIN pt_ranges pr ON pr.partida_id = lwr.partida_id
        AND NOT lwr.flg_rib
        AND lwr.rn > pr.rollos_start
        AND lwr.rn <= pr.rollos_start + pr.rollos
    ON CONFLICT (partida_id, lote_id) WHERE lote_id IS NOT NULL DO NOTHING
    RETURNING id AS opi_id, partida_id, lote_id
),
lrd_insert AS ( -- Step 1b: lote_rollo_detalle for each raw roll lote
    -- Raw ingress: no spec fields (ancho/malla/rendimiento/color set at dyeing step)
    -- guia_remision_id: NULL for now — will be wired when stub guias are created (point 3)
    INSERT INTO inventario.lote_rollo_detalle (
        lote_id,
        flg_tenido, flg_antipilling,
        fyh_cre
    )
    SELECT
        li.lote_id,
        false,
        false,
        li.fyh_cre
    FROM lote_insert li
    ON CONFLICT (lote_id) DO NOTHING
    RETURNING lote_id
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    destino_ubicacion_id, cantidad, documento_tipo, documento_id,
    usr_cre, fyh_cre, fecha_hora
)
SELECT
    ip.doc_movimiento_id,
    li.item_id,
    li.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_ING'),
    (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
    li.cantidad,
    'PARTIDA',
    li.partida_id,
    li.usr_cre,
    li.fyh_cre,
    li.fyh_cre
FROM lote_insert li
JOIN ingress_posting ip ON ip.partida_id = li.partida_id; 
-- ============================================================================
-- Use this if inventario.lote rows for documento_tipo='PARTIDA' already exist
-- (Steps 1 + 4 already ran) but opi/oppi need to be redone — e.g. after logic
-- changes to pxr_ranges or opi_insert without re-seeding lotes.
--
-- Prerequisites:
--   DELETE FROM mes.partida_paso_item
--   WHERE partida_componente_id IN (
--       SELECT id FROM mes.partida_componente
--       WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA')
--   );
--   DELETE FROM mes.partida_componente
--   WHERE lote_id IN (SELECT id FROM inventario.lote WHERE documento_tipo = 'PARTIDA');
--
-- NOTE: SERV_ING movements (Step 4) are NOT re-created here — they already exist.
-- Run Steps 5 onward after this snippet.
-- ============================================================================
-- WITH pxr_ranges AS (
--     SELECT
--         pxr.id                                                                          AS pxr_id,
--         pxr.partida_id,
--         tr.partida_tipo,
--         COALESCE(pxr.rollos, 0)                                                         AS rollos,
--         COALESCE(pxr.rib, 0)                                                            AS rib,
--         CASE WHEN tr.partida_tipo = 'NORMAL'
--              THEN COALESCE(SUM(COALESCE(pxr.rollos, 0)) OVER (
--                       PARTITION BY pxr.partida_id, tr.partida_tipo
--                       ORDER BY pxr.fecha, pxr.id
--                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
--                   ), 0)
--              ELSE 0
--         END                                                                             AS rollos_start,
--         CASE WHEN tr.partida_tipo = 'NORMAL'
--              THEN COALESCE(SUM(COALESCE(pxr.rib, 0)) OVER (
--                       PARTITION BY pxr.partida_id, tr.partida_tipo
--                       ORDER BY pxr.fecha, pxr.id
--                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
--                   ), 0)
--              ELSE 0
--         END                                                                             AS rib_start
--     FROM partida_x_recetas pxr
--     JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
--     WHERE pxr.receta_id IS NOT NULL AND pxr.flg_elm = false
-- ),
-- lote_existing AS (
--     SELECT
--         l.id AS lote_id, l.item_id, l.documento_id AS partida_id,
--         l.cantidad, l.propietario_id, l.usr_cre, l.fyh_cre,
--         ird.flg_rib,
--         ROW_NUMBER() OVER (PARTITION BY l.documento_id, ird.flg_rib ORDER BY l.id) AS rn
--     FROM inventario.lote l
--     JOIN item_rollo_detalle ird ON ird.item_id = l.item_id AND ird.flg_tenido = false
--     WHERE l.documento_tipo = 'PARTIDA'
-- ),
-- opi_insert AS (
--     INSERT INTO mes.partida_componente (partida_id, item_id, lote_id, ubicacion_id, usr_cre, fyh_cre)
--     SELECT
--         pr.pxr_id,
--         le.item_id,
--         le.lote_id,
--         (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
--         le.usr_cre,
--         le.fyh_cre
--     FROM lote_existing le
--     JOIN pxr_ranges pr ON pr.partida_id = le.partida_id
--         AND CASE WHEN le.flg_rib
--                  THEN le.rn > pr.rib_start    AND le.rn <= pr.rib_start    + pr.rib
--                  ELSE le.rn > pr.rollos_start AND le.rn <= pr.rollos_start + pr.rollos
--             END
--     RETURNING id AS opi_id, partida_id, lote_id
-- )
-- INSERT INTO mes.partida_paso_item (partida_paso_id, partida_componente_id, usr_cre, fyh_cre)
-- SELECT
--     opp.id,
--     opi.opi_id,
--     le.usr_cre,
--     le.fyh_cre
-- FROM opi_insert opi
-- JOIN mes.partida_paso opp
--     ON opp.partida_id = opi.partida_id AND opp.secuencia = 1
-- JOIN lote_existing le ON le.lote_id = opi.lote_id;

-- Step 5: PROD_CONSUMO — raw roll consumed by NORMAL paso only
-- REPROCESO pasos intentionally excluded: they share the same raw lotes via opi/oppi
-- for roll-count traceability, but no inventory debit is recorded for re-processing.
WITH egress_posting AS (
    SELECT t.id AS paso_id, nextval('inventario.mov_doc_seq') AS doc_movimiento_id
    FROM (
        SELECT DISTINCT opp.id
        FROM mes.partida_paso opp
        JOIN produccion_tenido pt_n ON pt_n.id = opp.id
        WHERE opp.secuencia = 1
          AND pt_n.tipo = 'Teñido'
          AND EXISTS (
              SELECT 1 FROM mes.partida_componente pc
              WHERE pc.partida_id = opp.partida_id AND pc.lote_id IS NOT NULL
          )
    ) t
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, cantidad, documento_tipo, documento_id,
    usr_cre, fyh_cre, fecha_hora
)
SELECT
    ep.doc_movimiento_id,
    l.item_id,
    l.id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_CONSUMO'),
    (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
    l.cantidad,
    'partida_paso',
    opp.id,
    l.usr_cre,
    l.fyh_cre,
    l.fyh_cre
FROM mes.partida_paso opp
JOIN mes.partida op ON op.id = opp.partida_id
JOIN mes.partida_componente pc ON pc.partida_id = op.id AND pc.lote_id IS NOT NULL
JOIN inventario.lote l ON l.id = pc.lote_id AND l.documento_tipo = 'PARTIDA'
JOIN egress_posting ep ON ep.paso_id = opp.id
WHERE opp.secuencia = 1;

-- ============================================================================
-- Step 6: Ghost egress — roll lotes with no paso assignment (SERV_EGR)
-- ============================================================================
-- Covers roll lotes that received a SERV_ING ingress (Step 1–4) and have an
-- partida_componente entry, but whose partida has no pasos
-- (receta_id was NULL), so Step 5's oppi JOIN never fired for them.
-- Without this, those lotes show as permanently in-stock (open balance).
--
-- Movement type: SERV_EGR — material dispatched back to client.
-- Scope:         only CERRADA partidas (estado_produccion = 'CERRADA') — in-progress rolls stay in stock.
-- Date:          partida.fyh_mod (last state change) → fyh_cre_tz → fyh_cre as fallback.
-- One doc_movimiento_id per partida — same grouping as ingress (Step 1–4).
-- ============================================================================

WITH ghost_source AS (
    -- Catches ALL roll lotes with no completed paso assignment:
    --   • lotes with opi but no oppi (assigned to op, paso link missing)
    --   • lotes with no opi at all (outside pt.rollos range, rib lotes, etc.)
    -- Both leave an open inventory balance without this egress.
    SELECT
        l.id                                                                        AS lote_id,
        l.item_id,
        l.cantidad,
        l.documento_id                                                              AS partida_id,
        l.usr_cre,
        p.fyh_cre                                                                   AS fyh_egr
    FROM inventario.lote l
    JOIN mes.partida p ON p.id = l.documento_id
    WHERE l.documento_tipo = 'PARTIDA'
      AND NOT EXISTS (
          SELECT 1
          FROM mes.partida_componente pc
          JOIN mes.partida_paso opp ON opp.partida_id = pc.partida_id AND opp.secuencia = 1
          JOIN produccion_tenido pt_n ON pt_n.id = opp.id
          WHERE pc.lote_id = l.id
            AND pt_n.tipo = 'Teñido'
      )
      AND (
          p.estado_produccion IN ('TECO', 'CERRADA', 'CANCELADA')
          OR p.estado_comercial IN ('ENTREGADA', 'ENTREGA_PARCIAL', 'DEVUELTA_PARCIAL', 'DEVUELTA_TOTAL')
      )
),
ghost_posting AS (
    SELECT partida_id, nextval('inventario.mov_doc_seq') AS doc_movimiento_id
    FROM (SELECT DISTINCT partida_id FROM ghost_source) t
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, cantidad, documento_tipo, documento_id,
    usr_cre, fyh_cre,fecha_hora
)
SELECT
    gp.doc_movimiento_id,
    gs.item_id,
    gs.lote_id,
    (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'SERV_EGR'),
    (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
    gs.cantidad,
    'PARTIDA',
    gs.partida_id,
    gs.usr_cre,
    gs.fyh_egr,
    gs.fyh_egr
FROM ghost_source gs
JOIN ghost_posting gp ON gp.partida_id = gs.partida_id;

COMMIT;
-- SELECT * FROM inventario.item_movimientos
-- WHERE documento_tipo IN ('partida_paso')
-- and item_movimiento_tipo_id IN ((SELECT id FROM inventario.item_movimiento_tipo
--      WHERE codigo IN ('VENTA_EGR' , 'SERV_EGR')))
-- ============================================================================
-- Steps 7–8: Dyed roll output + dispatch
-- ============================================================================
-- Applies to raw lotes on the LAST paso of their partida's chain.
-- Step 7 — PROD_ING: creates a new dyed roll lote (same item_id as raw lote)
--           linked to the last paso, ingressed at fecha_entrega.
--           Processing state (color, tenido, flg_tenido=true) is set on
--           lote_rollo_detalle populated at end of this file, not here.
-- Step 8 — SERV_EGR: dispatches the dyed lote back to the client.
--           Net stock effect = 0.
-- "Last paso" = the paso belonging to the op with the latest fyh_fin for
-- that partida. REPROCESO pasos share the raw lote via opi/oppi for traceability
-- but only the final paso produces the output and dispatch movements.
-- ============================================================================
WITH last_paso_per_partida AS (
    -- Last paso per partida by secuencia (= chronologically last dyeing run).
    SELECT DISTINCT ON (opp.partida_id)
        opp.partida_id,
        opp.id AS paso_id
    FROM mes.partida_paso opp
    ORDER BY opp.partida_id, opp.secuencia DESC
),
dyed_source AS (
    SELECT
        l.cantidad,
        l.propietario_id,
        l.usr_cre,
        l.item_id                                                                  AS dyed_item_id,
        lpp.paso_id,
        -- Reconstruct finish timestamp from produccion_tenido: start + duration.
        COALESCE(
            (
                (pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP
                    + INTERVAL '5 hours'
                    + COALESCE(pt.duracion::INTERVAL, INTERVAL '4 hours')
            )::TIMESTAMPTZ,
            p.fyh_cre
        )                                                                          AS fyh_out
    FROM inventario.lote l
    JOIN mes.partida_componente pc ON pc.lote_id = l.id
    JOIN last_paso_per_partida lpp ON lpp.partida_id = pc.partida_id
    JOIN mes.partida_paso opp ON opp.id = lpp.paso_id
    LEFT JOIN produccion_tenido pt ON pt.id = opp.id
    JOIN mes.partida p ON p.id = l.documento_id
    WHERE l.documento_tipo = 'PARTIDA'
),
posting AS (
    SELECT paso_id, nextval('inventario.mov_doc_seq') AS doc_movimiento_id
    FROM (SELECT DISTINCT paso_id FROM dyed_source) t
),
dyed_lote_insert AS (
    INSERT INTO inventario.lote (item_id, cantidad, documento_tipo, documento_id, propietario_id, usr_cre, fyh_cre)
    SELECT dyed_item_id, cantidad, 'partida_paso', paso_id, propietario_id, usr_cre, fyh_out
    FROM dyed_source
    RETURNING id AS lote_id, item_id, cantidad, documento_id AS paso_id, propietario_id, usr_cre, fyh_cre
),
prod_ing_insert AS (
    INSERT INTO inventario.item_movimientos (
        doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
        destino_ubicacion_id, cantidad, documento_tipo, documento_id,
        usr_cre, fyh_cre, fecha_hora
    )
    SELECT
        po.doc_movimiento_id,
        dl.item_id,
        dl.lote_id,
        (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'PROD_ING'),
        (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
        dl.cantidad,
        'partida_paso',
        dl.paso_id,
        dl.usr_cre,
        dl.fyh_cre,
        dl.fyh_cre
    FROM dyed_lote_insert dl
    JOIN posting po ON po.paso_id = dl.paso_id
)
INSERT INTO inventario.item_movimientos (
    doc_movimiento_id, item_id, lote_id, item_movimiento_tipo_id,
    origen_ubicacion_id, cantidad, documento_tipo, documento_id,
    usr_cre, fyh_cre, fecha_hora
)
SELECT
    po.doc_movimiento_id,
    dl.item_id,
    dl.lote_id,
    -- propietario_id = 1 means MLR owns the roll (MLR/* or OSWALDO/* client) → sale dispatch
    -- propietario_id != 1 means client owns the roll → service return dispatch
    (SELECT id FROM inventario.item_movimiento_tipo
     WHERE codigo = CASE WHEN dl.propietario_id = 1 THEN 'VENTA_EGR' ELSE 'SERV_EGR' END),
    (SELECT ub.id FROM inventario.ubicacion ub JOIN inventario.almacen alm ON alm.id = ub.almacen_id WHERE alm.codigo = 'ALM_CRU'),
    dl.cantidad,
    'partida_paso',
    dl.paso_id,
    dl.usr_cre,
    dl.fyh_cre,
    dl.fyh_cre
FROM dyed_lote_insert dl
JOIN posting po ON po.paso_id = dl.paso_id;

ALTER TABLE inventario.lote ENABLE TRIGGER trg_bi_lote_secuencia;

-- Backfill secuencia for migration lotes (trigger was disabled during bulk insert).
-- Assigns sequential numbers per year starting after any already-assigned values,
-- ordered by fyh_cre then id to be deterministic.
WITH max_per_year AS (
    SELECT date_part('year', fyh_cre)::int AS ano, MAX(secuencia) AS max_seq
    FROM inventario.lote
    WHERE secuencia IS NOT NULL
    GROUP BY 1
),
to_assign AS (
    SELECT
        l.id,
        date_part('year', l.fyh_cre)::int AS ano,
        ROW_NUMBER() OVER (PARTITION BY date_part('year', l.fyh_cre) ORDER BY l.fyh_cre, l.id) AS rn,
        COALESCE(m.max_seq, 0) AS offset
    FROM inventario.lote l
    LEFT JOIN max_per_year m ON m.ano = date_part('year', l.fyh_cre)::int
    WHERE l.secuencia IS NULL
)
UPDATE inventario.lote l
SET secuencia = ta.offset + ta.rn
FROM to_assign ta
WHERE l.id = ta.id;

-- Sync lote_secuencia_anual to the new max per year so the trigger
-- continues correctly from where the backfill left off.
INSERT INTO inventario.lote_secuencia_anual (ano, ultimo_valor)
SELECT date_part('year', fyh_cre)::int, MAX(secuencia)
FROM inventario.lote
WHERE secuencia IS NOT NULL
GROUP BY 1
ON CONFLICT (ano) DO UPDATE
    SET ultimo_valor = GREATEST(inventario.lote_secuencia_anual.ultimo_valor, EXCLUDED.ultimo_valor);

ALTER TABLE inventario.lote ALTER COLUMN secuencia SET NOT NULL;

-- ============================================================================
-- BACKFILL PESAJE  →  inventario.pesaje
-- ============================================================================
-- No per-roll weighing records existed in the legacy system.
-- We synthesize one pesaje row per roll lote using lote.cantidad as peso_real
-- (which equals peso_rollos/rollos — the average roll weight from the partida).
-- This satisfies the weighing gate (EXISTS pesaje WHERE lote_id = ?) for all
-- historical lotes so they can be processed through the new system without
-- being blocked as "unweighed".
-- ============================================================================
INSERT INTO inventario.pesaje (lote_id, tipo, peso_real, observacion, usr_cre, fyh_cre)
SELECT
    l.id,
    'INGRESO',
    l.cantidad,
    'Migración — peso promedio calculado de partida',
    l.usr_cre,
    l.fyh_cre
FROM inventario.lote l
WHERE l.documento_tipo = 'PARTIDA';

INSERT INTO mes.tiempos_estandar_tenido (valor_id, tenido_id, flg_antipilling, duracion, flg_activo)
SELECT DISTINCT ON (valor_id, tenido_id, adicional_id IS NOT NULL)
    valor_id,
    tenido_id,
    adicional_id IS NOT NULL,
    duracion,
    COALESCE(flg_activo, true)
FROM public.tiempos_estandar_tenido
WHERE duracion IS NOT NULL
  AND valor_id IS NOT NULL
  AND tenido_id IS NOT NULL
ORDER BY valor_id, tenido_id, (adicional_id IS NOT NULL),
         flg_activo DESC NULLS LAST, id DESC;

-- ============================================================================
-- mes.tiempos_estandar_lavado  ←  public.tiempos_estandar_lavado
-- ============================================================================
INSERT INTO mes.tiempos_estandar_lavado (tipo_lavado_mq_id, duracion, flg_activo)
SELECT tipo_lavado_mq_id, duracion, COALESCE(flg_activo, true)
FROM public.tiempos_estandar_lavado
WHERE duracion IS NOT NULL
  AND tipo_lavado_mq_id IS NOT NULL;

-- ============================================================================
-- DROP BRIDGE COLUMNS  →  tercero  (run manually after go-live stabilizes)
-- ============================================================================
-- cliente_id, cliente_id2, proveedor_id were temporary join bridges used only
-- during migration. Keep for a few months as a safety net, then drop.
-- ============================================================================
-- ALTER TABLE tercero
--     DROP COLUMN IF EXISTS cliente_id,
--     DROP COLUMN IF EXISTS cliente_id2,
--     DROP COLUMN IF EXISTS proveedor_id;

-- ── Step: inventario.lote_rollo_detalle population ────────────
-- Populates lote_rollo_detalle for remaining ROLLO lote origin types.
-- PARTIDA lotes are handled inline in the roll lote CTE above (lrd_insert).
-- Three remaining origin types:
--   GUIA_REMISION  → new-flow ingress rolls: billing anchor only, spec fields NULL
--   partida_paso → dyed rolls: full identity from mes.partida
--   CUADRE         → surplus rolls from stock count: no guia, no spec fields


INSERT INTO inventario.lote_rollo_detalle (
    lote_id,
    guia_remision_id,
    ancho,
    malla,
    rendimiento,
    color_x_cliente_id,
    tenido_id,
    flg_tenido,
    flg_antipilling,
    fyh_cre
)
-- New-flow ingress rolls (GUIA_REMISION) — guia IS the documento_id; spec fields not yet set
SELECT
    l.id,
    l.documento_id,
    NULL, NULL, NULL, NULL, NULL,
    false,
    false,
    l.fyh_cre
FROM inventario.lote l
JOIN item i       ON i.id = l.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
WHERE l.documento_tipo = 'GUIA_REMISION'
  AND l.fyh_elm IS NULL

UNION ALL

-- Dyed rolls — spec fields from partida directly; no guia for legacy PARTIDA-origin rolls
-- (legacy fabric rolls arrived via partida flow, not guia_remision, so guia_remision_id = NULL)
-- At insert time documento_tipo = 'partida_paso'; end-of-migration re-stamp updates
-- these lotes to 'partida_paso_ejecucion' after ejecucion rows are created.
SELECT
    l.id,
    NULL::bigint,
    op.ancho,
    op.malla,
    op.rendimiento,
    op.color_x_cliente_id,
    op.tenido_id,
    true,
    op.flg_antipilling,
    l.fyh_cre
FROM inventario.lote l
JOIN item i       ON i.id = l.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
JOIN mes.partida_paso opp ON opp.id = l.documento_id
JOIN mes.partida op       ON op.id = opp.partida_id
WHERE l.documento_tipo = 'partida_paso'
  AND l.fyh_elm IS NULL

UNION ALL

-- Surplus rolls from stock count — no ingress guia, no spec fields
SELECT
    l.id,
    NULL,
    NULL, NULL, NULL, NULL, NULL,
    false,
    false,
    l.fyh_cre
FROM inventario.lote l
JOIN item i       ON i.id = l.item_id
JOIN item_tipo it ON it.id = i.item_tipo_id AND it.codigo = 'ROLLO'
WHERE l.documento_tipo = 'CUADRE'
  AND l.fyh_elm IS NULL

ON CONFLICT (lote_id) DO NOTHING;

-- ============================================================================
-- END-OF-MIGRATION: partida_paso_ejecucion + document re-stamp
-- ============================================================================
-- Execution state was stamped as documento_tipo = 'partida_paso' throughout the
-- migration blocks above because partida_paso_ejecucion rows did not yet exist.
-- These three steps retroactively create the execution layer and re-stamp all
-- ledger rows to the correct 'partida_paso_ejecucion' document type.
-- ============================================================================

-- Step A: Create one partida_paso_ejecucion per historical paso.
-- Source: produccion_tenido (pt.id = opp.id via OVERRIDING SYSTEM VALUE in paso insert).
-- Estado = COMPLETADO when hora_fin is recorded; EN_PROCESO otherwise (rare).
INSERT INTO mes.partida_paso_ejecucion (
    partida_paso_id,
    estado,
    maquina_id,
    fyh_inicio,
    fyh_fin,
    usr_cre,
    fyh_cre
)
SELECT
    opp.id                                                                  AS partida_paso_id,
    CASE WHEN pt.hora_fin IS NOT NULL
         THEN 'COMPLETADO'::paso_ejecucion_estado_enum
         ELSE 'EN_PROCESO'::paso_ejecucion_estado_enum
    END                                                                     AS estado,
    opp.maquina_planificada_id                                              AS maquina_id,
    (
        (pt.fecha + COALESCE(pt.hora_inicio, '06:00'::time))::TIMESTAMP
            + INTERVAL '5 hours'
    )::TIMESTAMPTZ                                                          AS fyh_inicio,
    CASE WHEN pt.hora_fin IS NOT NULL
         THEN ((pt.fecha + pt.hora_fin)::TIMESTAMP + INTERVAL '5 hours')::TIMESTAMPTZ
         ELSE NULL
    END                                                                     AS fyh_fin,
    opp.usr_cre,
    opp.fyh_cre
FROM mes.partida_paso opp
JOIN produccion_tenido pt ON pt.id = opp.id
ON CONFLICT DO NOTHING;

SELECT setval(
    pg_get_serial_sequence('mes.partida_paso_ejecucion', 'id'),
    COALESCE((SELECT MAX(id) FROM mes.partida_paso_ejecucion), 1)
);

-- Step C: Re-stamp inventario.lote from 'partida_paso' → 'partida_paso_ejecucion'.
-- documento_id was the partida_paso.id; replace with the ejecucion.id for that paso.
UPDATE inventario.lote l
SET documento_tipo = 'partida_paso_ejecucion',
    documento_id   = pe.id
FROM mes.partida_paso_ejecucion pe
WHERE l.documento_tipo = 'partida_paso'
  AND l.documento_id   = pe.partida_paso_id;

-- Step D: Re-stamp inventario.item_movimientos (same pattern as lote).
UPDATE inventario.item_movimientos im
SET documento_tipo = 'partida_paso_ejecucion',
    documento_id   = pe.id
FROM mes.partida_paso_ejecucion pe
WHERE im.documento_tipo = 'partida_paso'
  AND im.documento_id   = pe.partida_paso_id;

-- ============================================================================
-- doc.catalogo_precios — migrate from legacy public.catalogo_precios
-- ============================================================================
-- Mapping:
--   tipo_articulo_id  → articulo_tipo_id  (table renamed in step 4)
-- Legacy adicional_id mapping:
--   adicional_id = 0 → TENIDO row, flg_antipilling = false (base recipe)
--   adicional_id > 0 → TENIDO row, flg_antipilling = true  (antipilling recipe, different costo_kg)
-- Both rows may have the same precio_kg (price negotiated at base level),
-- but costo_kg will differ once recipes are approved.
--   activo = 0 → fyh_elm = fyh_fin
--   activo = 1 → fyh_elm = NULL (active)
--   costo_kg   → NULL (no historical cost data in legacy)
--
-- ANTIPILLING wildcard rows: client-level service charge.
-- Urban = 0.15/kg, all others = 0.10/kg (hardcoded per legacy get_partidas_despacho).
DO $$
DECLARE
    v_tenido_op_id    SMALLINT;
    v_antipil_op_id   SMALLINT;
    v_urban_tercero_id INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'catalogo_precios'
    ) THEN
        RETURN;
    END IF;

    SELECT id INTO v_tenido_op_id  FROM mes.operacion WHERE codigo = 'TENIDO';
    SELECT id INTO v_antipil_op_id FROM mes.operacion WHERE codigo = 'ANTIPILLING';
    SELECT id INTO v_urban_tercero_id FROM tercero WHERE codigo = 'URBAN';

    -- TENIDO rows: base (adicional_id=0) and antipilling variant (adicional_id>0)
    INSERT INTO doc.catalogo_precios (
        operacion_id,
        color_x_cliente_id,
        articulo_tipo_id,
        tenido_id,
        fibra,
        flg_antipilling,
        precio_kg,
        fyh_elm,
        fyh_cre
    )
    SELECT
        v_tenido_op_id,
        cp.color_x_cliente_id,
        cp.tipo_articulo_id::smallint,
        cp.tenido_id,
        cp.fibra::smallint,
        (cp.adicional_id > 0),
        cp.precio_tenido,
        CASE WHEN cp.activo = 0 THEN cp.fyh_fin ELSE NULL END,
        cp.fyh_cre
    FROM public.catalogo_precios cp
    WHERE cp.color_x_cliente_id IS NULL
       OR EXISTS (SELECT 1 FROM color_x_cliente cxc WHERE cxc.id = cp.color_x_cliente_id)
    ON CONFLICT DO NOTHING;

    -- ANTIPILLING wildcard rows: one per client tier (Urban, everyone else)
    -- These are the service charge rows — never tied to a specific color/recipe.
    INSERT INTO doc.catalogo_precios (
        operacion_id, tercero_id, precio_kg, fyh_cre
    )
    VALUES
        (v_antipil_op_id, v_urban_tercero_id, 0.15, NOW()),
        (v_antipil_op_id, NULL,               0.10, NOW())
    ON CONFLICT DO NOTHING;
END;
$$;
SELECT setval(
    pg_get_serial_sequence('doc.guia_remision', 'id'),
    (SELECT MAX(id) FROM doc.guia_remision)
);
-- ── Sequences: reset all to MAX(id) post-migration ──────────────
SELECT setval(pg_get_serial_sequence('item',                           'id'),     COALESCE((SELECT MAX(id)     FROM item),                           1));
SELECT setval(pg_get_serial_sequence('tercero',                        'id'),     COALESCE((SELECT MAX(id)     FROM tercero),                        1));
SELECT setval(pg_get_serial_sequence('mes.partida',                    'id'),     COALESCE((SELECT MAX(id)     FROM mes.partida),                    1));
SELECT setval(pg_get_serial_sequence('mes.partida',                    'numero'), COALESCE((SELECT MAX(numero) FROM mes.partida),                    1));
SELECT setval(pg_get_serial_sequence('mes.partida_paso',               'id'),     COALESCE((SELECT MAX(id)     FROM mes.partida_paso),               1));
SELECT setval(pg_get_serial_sequence('mes.partida_paso_ejecucion',     'id'),     COALESCE((SELECT MAX(id)     FROM mes.partida_paso_ejecucion),     1));
SELECT setval(pg_get_serial_sequence('mes.partida_componente',         'id'),     COALESCE((SELECT MAX(id)     FROM mes.partida_componente),         1));
SELECT setval(pg_get_serial_sequence('mes.maquina',                    'id'),     COALESCE((SELECT MAX(id)     FROM mes.maquina),                    1));
SELECT setval(pg_get_serial_sequence('receta.tenido',                  'id'),     COALESCE((SELECT MAX(id)     FROM receta.tenido),                  1));
SELECT setval(pg_get_serial_sequence('receta.tenido_paso',             'id'),     COALESCE((SELECT MAX(id)     FROM receta.tenido_paso),             1));
SELECT setval(pg_get_serial_sequence('receta.tenido_paso_insumo',      'id'),     COALESCE((SELECT MAX(id)     FROM receta.tenido_paso_insumo),      1));
SELECT setval(pg_get_serial_sequence('receta.lavado_maquina',          'id'),     COALESCE((SELECT MAX(id)     FROM receta.lavado_maquina),          1));
SELECT setval(pg_get_serial_sequence('receta.lavado_maquina_paso',     'id'),     COALESCE((SELECT MAX(id)     FROM receta.lavado_maquina_paso),     1));
SELECT setval(pg_get_serial_sequence('inventario.lote',                'id'),     COALESCE((SELECT MAX(id)     FROM inventario.lote),                1));
SELECT setval(pg_get_serial_sequence('inventario.cuadre',              'id'),     COALESCE((SELECT MAX(id)     FROM inventario.cuadre),              1));
SELECT setval(pg_get_serial_sequence('inventario.item_movimientos',    'id'),     COALESCE((SELECT MAX(id)     FROM inventario.item_movimientos),    1));
SELECT setval(pg_get_serial_sequence('doc.compra',                     'id'),     COALESCE((SELECT MAX(id)     FROM doc.compra),                     1));
SELECT setval(pg_get_serial_sequence('doc.compra_detalle',             'id'),     COALESCE((SELECT MAX(id)     FROM doc.compra_detalle),             1));
SELECT setval(pg_get_serial_sequence('doc.factura_proveedor',          'id'),     COALESCE((SELECT MAX(id)     FROM doc.factura_proveedor),          1));
SELECT setval(pg_get_serial_sequence('doc.letra',                      'id'),     COALESCE((SELECT MAX(id)     FROM doc.letra),                     1));
SELECT setval(pg_get_serial_sequence('doc.guia_remision',              'id'),     COALESCE((SELECT MAX(id)     FROM doc.guia_remision),              1));
SELECT setval(pg_get_serial_sequence('doc.guia_remision_detalle',      'id'),     COALESCE((SELECT MAX(id)     FROM doc.guia_remision_detalle),      1));
SELECT setval(pg_get_serial_sequence('doc.factura',                    'id'),     COALESCE((SELECT MAX(id)     FROM doc.factura),                    1));
SELECT setval(pg_get_serial_sequence('doc.catalogo_precios',           'id'),     COALESCE((SELECT MAX(id)     FROM doc.catalogo_precios),           1));
SELECT setval(pg_get_serial_sequence('notification.notifications',           'id'),     COALESCE((SELECT MAX(id)     FROM notification.notifications),           1));

-- ── Initialize maintained stock balances from movement history ─
-- Runs after all movements are migrated. Trigger (step 12) takes over from here.

-- lote_saldo (MCHB): two explicit contributions per movement — no factor or imt join needed.
-- Ingress side credits destino; egress side debits origen. Both fire for single-row transfers.
INSERT INTO inventario.lote_saldo (lote_id, ubicacion_id, cantidad_actual)
SELECT lote_id, ubicacion_id, SUM(delta)
FROM (
    SELECT lote_id, destino_ubicacion_id AS ubicacion_id,  cantidad AS delta
    FROM inventario.item_movimientos
    WHERE lote_id IS NOT NULL AND destino_ubicacion_id IS NOT NULL
    UNION ALL
    SELECT lote_id, origen_ubicacion_id  AS ubicacion_id, -cantidad AS delta
    FROM inventario.item_movimientos
    WHERE lote_id IS NOT NULL AND origen_ubicacion_id IS NOT NULL
) sub
GROUP BY lote_id, ubicacion_id
ON CONFLICT (lote_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = EXCLUDED.cantidad_actual;

-- saldo_item (MARD): aggregate lote_saldo by (item, ubicacion).
INSERT INTO inventario.saldo_item (item_id, ubicacion_id, cantidad_actual)
SELECT l.item_id, ls.ubicacion_id, SUM(ls.cantidad_actual)
FROM inventario.lote_saldo ls
JOIN inventario.lote l ON l.id = ls.lote_id
GROUP BY l.item_id, ls.ubicacion_id
ON CONFLICT (item_id, ubicacion_id) DO UPDATE
    SET cantidad_actual = EXCLUDED.cantidad_actual;

