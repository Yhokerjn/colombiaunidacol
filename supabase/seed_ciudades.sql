-- =====================================================================
-- ColombiaUnida — Seed de Departamentos y Ciudades
-- Ejecutar DESPUÉS de 00_departamentos_ciudades_ddl.sql y ANTES de schema.sql
-- =====================================================================
-- Cobertura: las 32 capitales de departamento + Bogotá D.C. + los
-- municipios principales (mayor población / relevancia logística) de
-- cada departamento. No es el listado DIVIPOLA completo (1.122
-- municipios) — es "ciudades principales y municipios" tal como se
-- pidió. Si se necesita cobertura 100% completa, importar el CSV
-- oficial de DIVIPOLA del DANE con esta misma estructura.
--
-- dane_codigo de `ciudades`: por convención DIVIPOLA, el municipio
-- capital de un departamento tiene código = código_departamento + '001'
-- (ej. Cali = 76 + 001 = 76001). Esa regla es confiable y se aplica
-- aquí solo a las capitales. Para el resto de municipios el código de
-- 5 dígitos exacto no se incluye (se deja NULL) para no insertar un
-- código DIVIPOLA incorrecto — mejor vacío que un dato falso en un
-- sistema de emergencia. Se puede completar después importando DIVIPOLA.
-- =====================================================================

create extension if not exists unaccent;

insert into departamentos (nombre, dane_codigo) values
    ('Amazonas', '91'),
    ('Antioquia', '05'),
    ('Arauca', '81'),
    ('Atlántico', '08'),
    ('Bogotá D.C.', '11'),
    ('Bolívar', '13'),
    ('Boyacá', '15'),
    ('Caldas', '17'),
    ('Caquetá', '18'),
    ('Casanare', '85'),
    ('Cauca', '19'),
    ('Cesar', '20'),
    ('Chocó', '27'),
    ('Córdoba', '23'),
    ('Cundinamarca', '25'),
    ('Guainía', '94'),
    ('Guaviare', '95'),
    ('Huila', '41'),
    ('La Guajira', '44'),
    ('Magdalena', '47'),
    ('Meta', '50'),
    ('Nariño', '52'),
    ('Norte de Santander', '54'),
    ('Putumayo', '86'),
    ('Quindío', '63'),
    ('Risaralda', '66'),
    ('San Andrés y Providencia', '88'),
    ('Santander', '68'),
    ('Sucre', '70'),
    ('Tolima', '73'),
    ('Valle del Cauca', '76'),
    ('Vaupés', '97'),
    ('Vichada', '99')
on conflict (nombre) do nothing;

insert into ciudades (nombre, departamento_id, dane_codigo, slug)
select
    v.nombre,
    d.id,
    case when v.es_capital then d.dane_codigo || '001' else null end,
    regexp_replace(lower(unaccent(v.nombre)), '[^a-z0-9]+', '-', 'g')
from (values
    -- Bogotá D.C.
    ('Bogotá', 'Bogotá D.C.', true),

    -- Amazonas
    ('Leticia', 'Amazonas', true),
    ('Puerto Nariño', 'Amazonas', false),

    -- Antioquia
    ('Medellín', 'Antioquia', true),
    ('Bello', 'Antioquia', false),
    ('Itagüí', 'Antioquia', false),
    ('Envigado', 'Antioquia', false),
    ('Apartadó', 'Antioquia', false),
    ('Turbo', 'Antioquia', false),
    ('Rionegro', 'Antioquia', false),
    ('Sabaneta', 'Antioquia', false),
    ('Caucasia', 'Antioquia', false),
    ('Necoclí', 'Antioquia', false),

    -- Arauca
    ('Arauca', 'Arauca', true),
    ('Tame', 'Arauca', false),
    ('Saravena', 'Arauca', false),

    -- Atlántico
    ('Barranquilla', 'Atlántico', true),
    ('Soledad', 'Atlántico', false),
    ('Malambo', 'Atlántico', false),
    ('Sabanalarga', 'Atlántico', false),
    ('Puerto Colombia', 'Atlántico', false),

    -- Bolívar
    ('Cartagena', 'Bolívar', true),
    ('Magangué', 'Bolívar', false),
    ('Turbaco', 'Bolívar', false),
    ('Arjona', 'Bolívar', false),
    ('El Carmen de Bolívar', 'Bolívar', false),

    -- Boyacá
    ('Tunja', 'Boyacá', true),
    ('Duitama', 'Boyacá', false),
    ('Sogamoso', 'Boyacá', false),
    ('Chiquinquirá', 'Boyacá', false),
    ('Puerto Boyacá', 'Boyacá', false),

    -- Caldas
    ('Manizales', 'Caldas', true),
    ('La Dorada', 'Caldas', false),
    ('Chinchiná', 'Caldas', false),
    ('Villamaría', 'Caldas', false),

    -- Caquetá
    ('Florencia', 'Caquetá', true),
    ('San Vicente del Caguán', 'Caquetá', false),

    -- Casanare
    ('Yopal', 'Casanare', true),
    ('Aguazul', 'Casanare', false),
    ('Villanueva', 'Casanare', false),

    -- Cauca
    ('Popayán', 'Cauca', true),
    ('Santander de Quilichao', 'Cauca', false),
    ('El Bordo (Patía)', 'Cauca', false),

    -- Cesar
    ('Valledupar', 'Cesar', true),
    ('Aguachica', 'Cesar', false),
    ('Codazzi', 'Cesar', false),
    ('El Copey', 'Cesar', false),

    -- Chocó
    ('Quibdó', 'Chocó', true),
    ('Istmina', 'Chocó', false),
    ('Tadó', 'Chocó', false),

    -- Córdoba
    ('Montería', 'Córdoba', true),
    ('Cereté', 'Córdoba', false),
    ('Lorica', 'Córdoba', false),
    ('Sahagún', 'Córdoba', false),
    ('Tierralta', 'Córdoba', false),

    -- Cundinamarca
    ('Soacha', 'Cundinamarca', false),
    ('Girardot', 'Cundinamarca', false),
    ('Zipaquirá', 'Cundinamarca', false),
    ('Facatativá', 'Cundinamarca', false),
    ('Chía', 'Cundinamarca', false),
    ('Fusagasugá', 'Cundinamarca', false),
    ('Mosquera', 'Cundinamarca', false),
    ('Madrid', 'Cundinamarca', false),

    -- Guainía
    ('Inírida', 'Guainía', true),

    -- Guaviare
    ('San José del Guaviare', 'Guaviare', true),

    -- Huila
    ('Neiva', 'Huila', true),
    ('Pitalito', 'Huila', false),
    ('Garzón', 'Huila', false),

    -- La Guajira
    ('Riohacha', 'La Guajira', true),
    ('Maicao', 'La Guajira', false),
    ('Uribia', 'La Guajira', false),
    ('Fonseca', 'La Guajira', false),

    -- Magdalena
    ('Santa Marta', 'Magdalena', true),
    ('Ciénaga', 'Magdalena', false),
    ('Fundación', 'Magdalena', false),
    ('El Banco', 'Magdalena', false),

    -- Meta
    ('Villavicencio', 'Meta', true),
    ('Acacías', 'Meta', false),
    ('Granada', 'Meta', false),

    -- Nariño
    ('Pasto', 'Nariño', true),
    ('Tumaco', 'Nariño', false),
    ('Ipiales', 'Nariño', false),

    -- Norte de Santander
    ('Cúcuta', 'Norte de Santander', true),
    ('Ocaña', 'Norte de Santander', false),
    ('Pamplona', 'Norte de Santander', false),
    ('Villa del Rosario', 'Norte de Santander', false),

    -- Putumayo
    ('Mocoa', 'Putumayo', true),
    ('Puerto Asís', 'Putumayo', false),

    -- Quindío
    ('Armenia', 'Quindío', true),
    ('Calarcá', 'Quindío', false),
    ('Montenegro', 'Quindío', false),

    -- Risaralda
    ('Pereira', 'Risaralda', true),
    ('Dosquebradas', 'Risaralda', false),
    ('Santa Rosa de Cabal', 'Risaralda', false),

    -- San Andrés y Providencia
    ('San Andrés', 'San Andrés y Providencia', true),
    ('Providencia', 'San Andrés y Providencia', false),

    -- Santander
    ('Bucaramanga', 'Santander', true),
    ('Floridablanca', 'Santander', false),
    ('Girón', 'Santander', false),
    ('Piedecuesta', 'Santander', false),
    ('Barrancabermeja', 'Santander', false),
    ('San Gil', 'Santander', false),

    -- Sucre
    ('Sincelejo', 'Sucre', true),
    ('Corozal', 'Sucre', false),
    ('Sampués', 'Sucre', false),

    -- Tolima
    ('Ibagué', 'Tolima', true),
    ('Espinal', 'Tolima', false),
    ('Melgar', 'Tolima', false),
    ('Honda', 'Tolima', false),

    -- Valle del Cauca
    ('Cali', 'Valle del Cauca', true),
    ('Palmira', 'Valle del Cauca', false),
    ('Buenaventura', 'Valle del Cauca', false),
    ('Tuluá', 'Valle del Cauca', false),
    ('Cartago', 'Valle del Cauca', false),
    ('Buga', 'Valle del Cauca', false),
    ('Jamundí', 'Valle del Cauca', false),
    ('Yumbo', 'Valle del Cauca', false),

    -- Vaupés
    ('Mitú', 'Vaupés', true),

    -- Vichada
    ('Puerto Carreño', 'Vichada', true)
) as v(nombre, departamento, es_capital)
join departamentos d on d.nombre = v.departamento
on conflict (slug) do nothing;
