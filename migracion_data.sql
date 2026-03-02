-- MLR Database Migration Script
-- Migrates data from existing tables to new PostgreSQL schema
-- Execute after tablas.sql and funciones.sql are loaded

BEGIN;

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

-- ============================================================================
-- 0. articulo_tipo  (new table — old name was tipo_articulo)
-- ============================================================================
INSERT INTO articulo_tipo (id, nombre, codigo_canon)
OVERRIDING SYSTEM VALUE
SELECT id, tipo_articulo AS nombre, lower(unaccent(tipo_articulo))
FROM public.tipo_articulo;

SELECT setval(
    pg_get_serial_sequence('articulo_tipo', 'id'),
    COALESCE((SELECT MAX(id) FROM articulo_tipo), 1)
);

-- ============================================================================
-- 1. MASTER DATA MIGRATION - Public Schema
-- ===========================================================================
-- CREAR ROLLOS CRUDOS
SELECT  UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1');

WITH base AS (
   SELECT  UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
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
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    flg_tenido,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    false,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

-----MIGRAR ROLLOS RIB CRUDOS

WITH base AS (
   SELECT  UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C') codigo,
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
WHERE rib>0
GROUP BY 
UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-C'),
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Crudo',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
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
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    flg_rib,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

--------------------INSERTAR ITEM ROLLO teñido
WITH base AS (
   SELECT  UPPER('R-' || a.articulo||'-'|| COALESCE(fibra, '1')||'-T') codigo,
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
GROUP BY 
UPPER('R-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T'),
'Rollo ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
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
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    flg_tenido,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);
---- RIB TEÑIDO

WITH base AS (
   SELECT  UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T') codigo,
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido' nombre,
u.id unidad_id,
it.id item_tipo_id,
articulo_id,
COALESCE(fibra, '1') fibra 
FROM partida
JOIN articulo  a ON a.id = partida.articulo_id
JOIN item_tipo it ON it.codigo='ROLLO'
JOIN unidad u ON u.codigo = 'kg'
WHERE rib>0
GROUP BY 
UPPER('R-'||'RB-'|| a.articulo||'-'|| COALESCE(fibra, '1')||'-T'),
'Rollo Rib ' || a.articulo || ' ' || COALESCE(fibra, '1') || ' fibra(s) Teñido',
u.id,
it.id,
articulo_id,
COALESCE(fibra, '1')
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
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_rollo_detalle (
    item_id,
    articulo_id,
    fibra,
    flg_rib,
    flg_tenido,
    fyh_cre)
SELECT
    i.id,
    b.articulo_id,
    b.fibra,
    true,
    true,
    NOW()
FROM ins_item i
JOIN base b USING (codigo);

-- ============================================================================
-- MIGRAR INSUMOS
-- ============================================================================
SELECT 'I-' ||
CASE tipo WHEN 'directo' THEN 'COL' WHEN 'reactivo' THEN 'COL' WHEN 'disperso' THEN 'COL' WHEN 'auxiliar' THEN 'AUX' WHEN 'quimico' THEN 'QUIM' END || '-' ||
CASE tipo WHEN 'directo' THEN 'DIR-' WHEN 'reactivo' THEN 'RX-' WHEN 'disperso' THEN 'DIS-' ELSE '' END ||
UPPER(trim(both '-' from regexp_replace(regexp_replace(i.insumo COLLATE "C", '\s+', ' ', 'g'), '[^A-Z0-9]+', '-', 'g'))) codigo,
i.insumo nombre,
u.id unidad_id,
i.medida,
it.id item_tipo_id,
it2.id insumo_tipo_id,
ct.id colorante_tipo_id,
insumo_id
FROM insumo i
LEFT JOIN item_tipo it ON it.codigo = 'INSUMO'
LEFT JOIN unidad u ON u.codigo = 'kg'
LEFT JOIN insumo_tipo it2 ON it2.nombre = CASE tipo WHEN 'directo' THEN 'colorante' WHEN 'reactivo' THEN 'colorante' WHEN 'disperso' THEN 'colorante' ELSE i.tipo::text END ---case when diperso,reactivo or directo then colorante
LEFT JOIN colorante_tipo ct ON ct.nombre=i.tipo::text;

with base AS(
    SELECT 'I-' ||
CASE tipo WHEN 'directo' THEN 'COL' WHEN 'reactivo' THEN 'COL' WHEN 'disperso' THEN 'COL' WHEN 'auxiliar' THEN 'AUX' WHEN 'quimico' THEN 'QUIM' END || '-' ||
CASE tipo WHEN 'directo' THEN 'DIR-' WHEN 'reactivo' THEN 'RX-' WHEN 'disperso' THEN 'DIS-' ELSE '' END ||
UPPER(trim(both '-' from regexp_replace(regexp_replace(i.insumo COLLATE "C", '\s+', ' ', 'g'), '[^A-Z0-9]+', '-', 'g'))) codigo,
i.insumo nombre,
u.id unidad_id,
i.medida,
it.id item_tipo_id,
it2.id insumo_tipo_id,
ct.id colorante_tipo_id,
i.id
FROM insumo i
LEFT JOIN item_tipo it ON it.codigo = 'INSUMO'
LEFT JOIN unidad u ON u.codigo = 'kg'
LEFT JOIN insumo_tipo it2 ON it2.nombre = CASE tipo WHEN 'directo' THEN 'colorante' WHEN 'reactivo' THEN 'colorante' WHEN 'disperso' THEN 'colorante' ELSE i.tipo::text END ---case when diperso,reactivo or directo then colorante
LEFT JOIN colorante_tipo ct ON ct.nombre=i.tipo::text
),
ins as(
    INSERT INTO item (
        codigo,
        nombre,
        item_tipo_id,
        unidad_id,
        fyh_cre,
        legacy_id
    )
    SELECT
        b.codigo,
        b.nombre,
        b.item_tipo_id,
        b.unidad_id,
        NOW(),
        id
    FROM base b
    -- ON CONFLICT (codigo_canon) DO NOTHING
    RETURNING id, codigo
)
INSERT INTO item_insumo_detalle(
    item_id,
    medida,
    insumo_tipo_id,
    colorante_tipo_id,
    fyh_cre
)
SELECT
    i.id,
    b.medida,
    b.insumo_tipo_id,
    b.colorante_tipo_id,
    NOW()
FROM ins i
JOIN base b USING (codigo);


-- ============================================================================
-- CREAR ALMACENES
-- ============================================================================

INSERT INTO inventario.almacen(codigo,nombre,fyh_cre)
VALUES ('ALM-INS', 'Almacén de Insumos', NOW()),
       ('ALM-CRU', 'Almacén de Crudo', NOW()),
       ('ALM-PT', 'Almacén de Productos Terminados', NOW());

INSERT INTO inventario.ubicacion(almacen_id,codigo,nombre,fyh_cre)
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM-INS'
UNION ALL
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM-CRU'
UNION ALL
SELECT a.id, 'UBI-01', 'Ubicación 1',NOW()
FROM inventario.almacen a
WHERE a.codigo = 'ALM-PT';

-- ============================================================================
-- MIGRAR PARTIDAS
-- ============================================================================
--Mapear Estados existentes
-- SELECT '''' || estado || '''' AS estado FROM estado
UPDATE partida
SET fyh_cre_tz=fyh_cre + INTERVAL '5 hours'
WHERE fyh_cre_tz='2025-09-11 22:53:28.212517+00';
UPDATE estado
SET estado_produccion = CASE estado
    WHEN 'Para Programar' THEN 'CREADA'::orden_produccion_estado_enum
    WHEN 'Programado' THEN 'PROGRAMADA'::orden_produccion_estado_enum
    WHEN 'En Proceso Teñido' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Teñido' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Lavado Hidro' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Secado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Para Despachar' THEN 'TECO'::orden_produccion_estado_enum
    WHEN 'Despachado' THEN 'CERRADA'::orden_produccion_estado_enum
    WHEN 'Devolución' THEN 'CERRADA'::orden_produccion_estado_enum
    WHEN 'Observado' THEN 'TECO'::orden_produccion_estado_enum
    WHEN 'Reprocesado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'En Proceso Reproceso' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Planchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Replanchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Termofijado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    WHEN 'Perchado' THEN 'EN_PROCESO'::orden_produccion_estado_enum
    ELSE
    'CERRADA'::orden_produccion_estado_enum
END,
estado_comercial = CASE estado
 WHEN 'Para Programar' THEN 'CREADA'::partida_estado_enum
    WHEN 'Programado' THEN 'CONFIRMADA'::partida_estado_enum
    WHEN 'En Proceso Teñido' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Teñido' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Lavado Hidro' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Secado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Para Despachar' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Despachado' THEN 'ENTREGADA'::partida_estado_enum
    WHEN 'Devolución' THEN 'DEVUELTA_PARCIAL'::partida_estado_enum
    WHEN 'Observado' THEN 'ENTREGADA'::partida_estado_enum
    WHEN 'Reprocesado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'En Proceso Reproceso' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Planchado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Replanchado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Termofijado' THEN 'EN_PRODUCCION'::partida_estado_enum
    WHEN 'Perchado' THEN 'EN_PRODUCCION'::partida_estado_enum
    ELSE 'CERRADA'::partida_estado_enum
     END

-- SELECT * FROM partida LIMIT 100
-- SELECT * FROM partida_estado_historial

SELECT ROW_NUMBER() OVER (PARTITION BY peh.partida_id ORDER BY peh.id desc) rw,peh.*,e.estado FROM partida_estado_historial peh
LEFT JOIN estado e ON e.id=peh.estado_id
ORDER BY partida_id;

WITH ult_estado as(SELECT ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY id desc) rw,* FROM partida_estado_historial)
,base as(SELECT 
pp.id,
pp.codigo,pp.prioridad_id,pp.cliente_id,
pp.tenido_id,
pp.articulo_id, pp.malla,pp.rendimiento,
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
   INSERT INTO doc.partida (
    id,
    numero,
    prioridad_id,
    cliente_id,
    color_x_cliente_id,
    tenido_id,
    articulo_id,
    fibra,
    malla,
    rendimiento,
    ancho
    estado,
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
    p.cliente_id,
    p.color_x_cliente_id,
    p.tenido_id,
    p.articulo_id,
    p.fibra,
    p.malla,
    p.rendimiento,
    p.ancho,
    p.estado_comercial,
    p.fecha_registro,
    p.fecha_registro,
    p.fecha_entrega,
    p.usr_cre,
    p.fyh_cre_tz
FROM base p
RETURNING id
)    INSERT INTO doc.partida_detalle (
        partida_id,
        item_id,
        cantidad,
        usr_cre,
        fyh_cre
    )
    SELECT
        p.id,
        ird.item_id,
        CASE WHEN ird.flg_rib THEN p.rib ELSE p.rollos END,
        p.usr_cre,
        p.fyh_cre_tz
    FROM base p
    LEFT JOIN item_rollo_detalle ird
    ON ird.articulo_id=p.articulo_id AND flg_tenido=true AND (flg_rib=false OR (flg_rib AND p.rib>0))
    AND COALESCE(p.fibra,1)=ird.fibra;
SELECT setval(
  pg_get_serial_sequence('doc.partida', 'id'),
  (SELECT MAX(id) FROM doc.partida)
);
SELECT setval(
  pg_get_serial_sequence('doc.partida', 'numero'),
  (SELECT MAX(numero) FROM doc.partida)
);


--============================================
--EJECUTAR ESTA SECCION MANUALMENTE
--============================================
UPDATE doc.partida SET flg_antipilling=(CASE p.adicional_id WHEN 1 THEN true ELSE false END) FROM partida p WHERE p.id=doc.partida.id


INSERT INTO mes.orden_produccion(
  partida_id,
  tipo,
  estado,
  fyh_cre,
  fyh_inicio,
  fyh_fin
)
SELECT 
  p.id partida_id,
  'NORMAL' tipo,
  CASE COALESCE(p.estado,'ENTREGADA')
  WHEN 'CONFIRMADA' THEN 'PLANIFICADA'::orden_produccion_estado_enum
  WHEN 'ENTREGADA' THEN 'CERRADA'::orden_produccion_estado_enum
  WHEN 'EN_PRODUCCION' THEN 'EN_PROCESO'::orden_produccion_estado_enum
  END estado,
  NOW() fyh_cre,
  pp.fecha_registro fyh_inicio,
  pp.fecha_entrega fyh_fin
FROM doc.partida p
LEFT JOIN public.partida pp ON pp.id=p.id
;

---INSERTAR REPROCESOS
INSERT INTO mes.orden_produccion(
  partida_id,
  tipo,
  estado,
  fyh_cre,
  fyh_inicio,
  fyh_fin
)
WITH ult_estado as(SELECT ROW_NUMBER() OVER (PARTITION BY partida_id ORDER BY id desc) rw,* FROM partida_estado_historial)
SELECT p.id,'REPROCESO' tipo, 'CERRADA',NOW() fyh_cre,   
ue.fecha_ejecucion fyh_inicio,
  ue.fecha_ejecucion fyh_fin
FROM doc.partida p
LEFT JOIN public.partida pp ON pp.id=p.id
LEFT JOIN ult_estado ue ON p.id = ue.partida_id
LEFT JOIN estado e ON e.id=ue.estado_id
WHERE e.estado LIKE '%Reprocesado%'
GROUP BY 1,2,3,4,5
--===========================================
--Migrar pasos
--===========================================
SELECT * FROM tipo_receta; 
-- Add column with FK
ALTER TABLE tipo_receta ADD COLUMN operacion_id SMALLINT;
ALTER TABLE tipo_receta ADD CONSTRAINT fk_tipo_receta_operacion 
    FOREIGN KEY (operacion_id) REFERENCES mes.operacion(id);

-- Update statements
UPDATE tipo_receta SET operacion_id = (SELECT id FROM mes.operacion WHERE nombre = 'TEÑIDO')
WHERE tipo_receta IN ('Teñido', 'Reteñido', 'Teñido a Negro', 'Desmontado + Reteñido', 'Reproceso Matizado');

UPDATE tipo_receta SET operacion_id = (SELECT id FROM mes.operacion WHERE nombre = 'LAVADO_HIDRO')
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
('MAQ-TEN',    'Maquina de Teñido'),
('HIDRO',      'Hidroextractora'),
('COMPACT',    'Compactadora'),
('PERCH',      'Perchadora'),
('PREP',       'Preparadora'),
('SEC',        'Secadora'),
('TERMO',      'Termofijadora'),
('VOLT',       'Volteadora'),
('BOMBA',      'Bomba de Agua'),
('POZO',       'Pozo de Agua'),
('ABLAND',     'Ablandador'),
('COMPR',      'Compresor'),
('CALDERO',    'Caldero')
ON CONFLICT (codigo) DO NOTHING;

-- Migrate maquina records with preserved IDs
INSERT INTO mes.maquina (
    id,
    codigo,
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
    'MAQ-' || LPAD(m.id::text, 3, '0') AS codigo,
    m.nombre,
    CASE m.ubicacion
        WHEN 'Maq Teñido'      THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'MAQ-TEN')
        WHEN 'Hidro'           THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'HIDRO')
        WHEN 'Compactadora'    THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'COMPACT')
        WHEN 'Percha'          THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'PERCH')
        WHEN 'Preparadora'     THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'PREP')
        WHEN 'Secadora'        THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'SEC')
        WHEN 'Termofijadora'   THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'TERMO')
        WHEN 'Volteadora'      THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'VOLT')
        WHEN 'Bombas de Agua'  THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'BOMBA')
        WHEN 'Pozo/Falta de Agua' THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'POZO')
        WHEN 'Ablandador'      THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'ABLAND')
        WHEN 'Compresor'       THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'COMPR')
        WHEN 'Caldero'         THEN (SELECT id FROM mes.maquina_tipo WHERE codigo = 'CALDERO')
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
-- LEFT JOIN mes.orden_produccion op ON op.partida_id = pxr.partida_id 
-- AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
-- WHERE op.id IS NULL
-- )SELECT DISTINCT tipo FROM mes.orden_produccion WHERE partida_id IN (SELECT partida_id FROM o)

------- Ver breakdown de los casos/ orden de ejecucion para ver si son parte de la produccion normal o reprocesos no registrados
-- WITH o AS (
-- SELECT op.id,pxr.partida_id
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- LEFT JOIN mes.orden_produccion op ON op.partida_id = pxr.partida_id 
-- AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
-- WHERE op.id IS NULL
-- )SELECT  pxr.partida_id, tr.tipo_receta,pxr.fecha
-- FROM partida_x_recetas pxr
-- LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
-- WHERE pxr.partida_id IN (SELECT partida_id FROM partida_x_recetas GROUP BY partida_id HAVING COUNT(*) > 1)
-- AND flg_elm=false AND tipo_receta_id IS NOT NULL AND partida_id IN (SELECT partida_id FROM o)
-- ORDER BY 1,3; 
-----SE CONFIRMA QUE TODOS LOS QUE nO JOINEAN SON PROQUE SON REPROCESOS O AJUSTES NO REGISTRADOS COMO TAL, se procede a INSERTAR LAS ORDENES DE PRODUCCION ADECUADAS
INSERT INTO mes.orden_produccion(
  partida_id,
  tipo,
  estado,
  fyh_cre,
  fyh_inicio,
  fyh_fin
)
WITH o AS (
SELECT op.id,pxr.partida_id
FROM partida_x_recetas pxr
LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
LEFT JOIN mes.orden_produccion op ON op.partida_id = pxr.partida_id 
AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
WHERE op.id IS NULL
)SELECT  pxr.partida_id, 'REPROCESO', 'CERRADA', pxr.fyh_cre, pxr.fecha, pxr.fecha
FROM partida_x_recetas pxr
WHERE flg_elm=false AND tipo_receta_id IS NOT NULL AND partida_id IN (SELECT partida_id FROM o)


------INSERTAR PRIMERO TEÑIDOS como primer paso de la orden de produccion default de todas las partidas
INSERT INTO mes.orden_produccion_paso(
orden_produccion_id,
secuencia,operacion_id,maquina_asignada_id,relacion_bano,receta_id,fyh_inicio,fyh_fin,
fyh_cre,
estado
)
SELECT op.id,
row_NUMBER() OVER (PARTITION BY op.id ORDER BY pxr.fecha,pxr.fyh_cre) AS secuencia,
tr.operacion_id,
pxr.maquina_id,
COALESCE(relacion_bano,m."RB"),
pxr.receta_id,
pxr.fecha,
pxr.fecha,
pxr.fyh_cre,
'COMPLETADO'
FROM partida_x_recetas pxr
LEFT JOIN tipo_receta tr ON tr.id = pxr.tipo_receta_id
LEFT JOIN public.maquina m ON m.id=pxr.maquina_id
LEFT JOIN mes.orden_produccion op ON op.partida_id = pxr.partida_id 
AND ((op.tipo = 'NORMAL' AND tipo_receta='Teñido') OR (op.tipo = 'REPROCESO' AND tipo_receta!='Teñido'))
WHERE pxr.receta_id IS not NULL;

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
SELECT i.id, it.id, i.cantidad, i.usr_cre, i.fyh_cre
FROM inventario i
LEFT JOIN insumo_x_proveedor ip ON ip.id=i.insumo_x_proveedor_id
LEFT JOIN item it ON it.legacy_id=ip.insumo_id
WHERE i.cantidad>0
GROUP BY 1,2,3,4,5
;

SELECT setval(
    pg_get_serial_sequence('inventario.lote', 'id'),
    (SELECT MAX(id) FROM inventario.lote)
);

UPDATE inventario.lote 
SET item_id = item.id
FROM inventario i 
JOIN entrada_inventario_detalle eid ON i.entrada_inventario_detalle_id=eid.id
LEFT JOIN item ON item.legacy_id = eid.insumo_id
WHERE i.id=inventario.lote.id and item_id IS NULL




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
--   compra            → lightweight header; factura_proveedor_id nullable (invoice may arrive later)
--   compra_detalle    → line items; insumo_id resolved → item_id via item.legacy_id
--   compra_guia_remision → junction written by the guia block below; no action needed here
--   letra             → re-linked from compra → factura_proveedor chain
-- ============================================================================

-- Step 1: doc.factura_proveedor
-- Sourced from public.compra rows that have a parseable 'SERIE-CORRELATIVO' factura.
-- subtotal/igv breakdown is not available in legacy data; total carries the full amount.
-- Rows with missing or malformed factura are skipped (they produce a compra with NULL factura_proveedor_id).
-- Run the orphan check query below before go-live to assess the gap.
INSERT INTO doc.factura_proveedor (
    proveedor_id,
    serie,
    numero,
    fecha_emision,
    fecha_vencimiento,
    tipo_pago,
    moneda,
    subtotal,
    igv,
    total,
    estado_pago,
    usr_cre,
    fyh_cre
)
SELECT
    c.proveedor_id,
    SPLIT_PART(c.factura, '-', 1)                    AS serie,
    SPLIT_PART(c.factura, '-', 2)::INT               AS numero,
    COALESCE(c.fecha_giro, c.fecha_remision)         AS fecha_emision,
    c.fecha_vencimiento,
    c.tipo_pago,
    'USD'::CHAR(3),
    0              AS subtotal,   -- no legacy breakdown available
    0              AS igv,
    c.total_usd    AS total,
    c.estado_pago,
    NULLIF(c.usr_cre, 'authenticated')::INT,
    c.fyh_cre_tz
FROM public.compra c
WHERE c.factura IS NOT NULL
  AND c.factura LIKE '%-%'         -- must be parseable as SERIE-CORRELATIVO
  AND c.proveedor_id IS NOT NULL;

-- Orphan check: compras with a factura that couldn't be parsed → no factura_proveedor created
-- SELECT id, factura FROM public.compra WHERE factura IS NOT NULL AND factura NOT LIKE '%-%';


-- Step 2: doc.compra  (OVERRIDING SYSTEM VALUE preserves public.compra.id for FK compatibility)
-- factura_proveedor_id is NULL for compras that had no factura or an unparseable one.
INSERT INTO doc.compra (
    id,
    proveedor_id,
    factura_proveedor_id,
    fecha,
    usr_cre,
    fyh_cre
)
OVERRIDING SYSTEM VALUE
SELECT
    c.id,
    c.proveedor_id,
    fp.id,
    COALESCE(c.fecha_remision, c.fyh_cre_tz::DATE) AS fecha,
    NULLIF(c.usr_cre, 'authenticated')::INT,
    c.fyh_cre_tz
FROM public.compra c
LEFT JOIN doc.factura_proveedor fp
    ON  fp.proveedor_id = c.proveedor_id
    AND fp.serie        = SPLIT_PART(c.factura, '-', 1)
    AND fp.numero       = SPLIT_PART(c.factura, '-', 2)::INT
WHERE c.proveedor_id IS NOT NULL;

SELECT setval(
    pg_get_serial_sequence('doc.compra', 'id'),
    (SELECT MAX(id) FROM doc.compra)
);


-- Step 3: doc.compra_detalle  (from public.compra_x_insumo)
-- insumo_id → item_id resolved via item.legacy_id populated in the insumo migration above.
-- Rows where legacy_id has no match are silently dropped; run the gap check below first.
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
JOIN item it ON it.legacy_id = cxi.insumo_id
WHERE cxi.compra_id IN (SELECT id FROM doc.compra);

-- Gap check: line items whose insumo_id didn't resolve to any item
-- SELECT cxi.compra_id, cxi.insumo_id
-- FROM public.compra_x_insumo cxi
-- LEFT JOIN item it ON it.legacy_id = cxi.insumo_id
-- WHERE it.id IS NULL;


-- Step 4: doc.letra  (from public.letra_compra)
-- Old letras were tied to compra_id; new letras require factura_proveedor_id.
-- Migration path: letra_compra.compra_id → doc.compra.factura_proveedor_id.
-- Letras on compras with no linked factura_proveedor cannot be migrated automatically;
-- run the unmigrated check below and handle manually if the count is significant.
-- Enum mapping: 'emitida' → 'pendiente'  (closest semantic match in new enum)
--               'pagada'  → 'pagada'
INSERT INTO doc.letra (
    factura_proveedor_id,
    numero,
    monto,
    fecha_giro,
    fecha_vencimiento,
    estado,
    fecha_pago,
    observacion,
    fyh_cre
)
SELECT
    dc.factura_proveedor_id,
    lc.numero_letra,
    lc.monto_usd,
    lc.fecha_emision         AS fecha_giro,
    lc.fecha_vencimiento,
    CASE lc.estado
        WHEN 'emitida' THEN 'pendiente'::letra_estado_enum
        WHEN 'pagada'  THEN 'pagada'::letra_estado_enum
        ELSE                'pendiente'::letra_estado_enum
    END,
    lc.fecha_pago,
    lc.observaciones,
    COALESCE(lc.fyh_cre_tz, lc.fyh_cre::TIMESTAMPTZ)
FROM public.letra_compra lc
JOIN doc.compra dc ON dc.id = lc.compra_id
WHERE dc.factura_proveedor_id IS NOT NULL;

-- Unmigrated letras: compras that had letras but no linked factura
-- SELECT lc.id, lc.compra_id, lc.numero_letra, lc.monto_usd
-- FROM public.letra_compra lc
-- JOIN doc.compra dc ON dc.id = lc.compra_id
-- WHERE dc.factura_proveedor_id IS NULL;

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
        NULLIF(c.usr_cre, 'authenticated')::int AS usr_cre,
        CASE 
            WHEN inv.rw = 1 THEN SPLIT_PART(c.guia_remision, '-', 1)
            ELSE SPLIT_PART(c.guia_remision, '-', 1)  -- same serie?
        END AS serie,
        CASE 
            WHEN inv.rw = 1 THEN SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1)
            ELSE SUBSTRING(c.guia_remision FROM POSITION('-' IN c.guia_remision) + 1) || '-' || inv.rw::text
        END AS correlativo
    FROM inv
    JOIN compra c ON c.id = inv.compra_id
),
inserted_guias AS (
    INSERT INTO doc.guia_remision (
        guia_remision_tipo_id, serie, correlativo, 
        emisor_proveedor_id, fecha_emision, usr_cre, fyh_cre
    )
    SELECT 
        (SELECT id FROM doc.guia_remision_tipo WHERE codigo = 'COMPRA_INGRESO'),
        serie,
        correlativo,
        proveedor_id,
        fecha_remision::date,
        usr_cre,
        fyh_cre
    FROM compra_data
    GROUP BY 1,2,3,4,5,6,7
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
JOIN doc.guia_remision ON doc.guia_remision.id = l.documento_id AND l.documento_tipo='GUIA_REMISION'

 

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
--     JOIN item ON item.legacy_id = ip.item_id
-- )
-- UPDATE inventario.lote 
-- SET tipo_documento = 'guia_remision',
-- documento_id = i.documento_id
-- FROM compra c 
-- JOIN inv ON inv.compra_id = c.id
-- WHERE c.inventario_id = inventario.lote.id;

-------------------ACTUALIZAR DOC DE ENTRADADAS POR AJUSTES y/o CUADRES
--pendiente
UPDATE inventario.lote 
SET documento_tipo = 'CUADRE_INVENTARIO',
documento_id = ci.id
FROM inventario i
JOIN entrada_inventario_detalle eid ON i.entrada_inventario_detalle_id=eid.id
JOIN entrada_inventario ei ON ei.id=eid.entrada_inventario_id
JOIN cuadre_inventario ci ON ci.fecha_cierre = ei.fyh_solicitud_tz
WHERE ei.motivo IN ('ajuste','reconteo') AND inventario.lote.id = i.id;


----PENDIENTE LIMPIAR id de documento de movimientos que NO son de cuadres
-- SELECT l.*,i.*
-- FROM inventario.lote l
-- JOIN inventario i ON i.id=l.id
-- JOIN entrada_inventario_detalle eid ON i.entrada_inventario_detalle_id=eid.id
-- JOIN entrada_inventario ei ON ei.id=eid.entrada_inventario_id
-- LEFT JOIN cuadre_inventario ci ON ci.fecha_cierre = ei.fyh_solicitud_tz
-- WHERE ei.motivo IN ('ajuste','reconteo') AND ci.id IS NOT NULL

--REGISTRAR MOVIMIENTO INICIAL
INSERT INTO inventario.item_movimientos(
    item_id, lote_id, item_movimiento_tipo_id, destino_ubicacion_id,cantidad,documento_tipo, documento_id, observacion,usr_cre, fyh_cre
)
SELECT 
    i.item_id,
    i.id,
    CASE WHEN i.documento_tipo = 'guia_remision' THEN (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'COMPRA_ING') ELSE (SELECT id FROM inventario.item_movimiento_tipo WHERE codigo = 'AJUSTE_POS') END,
    (SELECT inventario.ubicacion.id FROM inventario.ubicacion JOIN inventario.almacen ON inventario.almacen.id = inventario.ubicacion.almacen_id WHERE inventario.almacen.codigo = 'ALM-INS'),
    i.cantidad,
    i.documento_tipo,
    i.documento_id,
    'Migración Inicial',
    i.usr_cre,
    i.fyh_cre
FROM inventario.lote i
WHERE i.cantidad > 0


