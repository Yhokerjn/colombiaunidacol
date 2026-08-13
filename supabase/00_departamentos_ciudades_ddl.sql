-- =====================================================================
-- ColombiaUnida — DDL de departamentos + ciudades (CONTRATO nuevo)
-- =====================================================================
--
-- IMPORTANTE — por qué existe este archivo:
-- El `schema.sql` que ya está en este repo tiene una tabla `ciudades`
-- VIEJA (bigserial, columna `departamento` de tipo text, columna `tipo`,
-- sin `departamento_id`, sin `dane_codigo`, sin `slug`, y no existe
-- ninguna tabla `departamentos`). Esa versión es anterior al "CONTRATO
-- DE ARQUITECTURA" que se está implementando ahora — y de hecho
-- `supabase/functions/submit-reporte/index.ts` YA fue escrito contra el
-- contrato nuevo (usa `ciudad_id`, `ciudad_nombre`, `rate_limit_log`,
-- `buscar_duplicado_persona`), así que el proyecto está a mitad de
-- migración: el Edge Function ya espera el esquema nuevo, pero
-- `schema.sql` todavía no lo tiene.
--
-- Este archivo crea ÚNICAMENTE `departamentos` y `ciudades` tal como
-- las define el contrato, para que los seeds de este mismo pedido
-- (01_departamentos_seed.sql, 02_ciudades_fallback_seed.sql,
-- seed_ciudades.ts) tengan dónde insertar. No toca `personas`,
-- `acopios`, `contadores_cache`, `rate_limit_log` ni el resto del
-- contrato — eso es una migración más grande, fuera del alcance de
-- "poblar departamentos y ciudades", y no se hizo aquí para no tocar
-- datos existentes de personas/acopios sin que lo pidas explícitamente.
--
-- Ejecutar en: Supabase Dashboard > SQL Editor > New query
-- (antes de 01_departamentos_seed.sql y 02_ciudades_fallback_seed.sql)
-- =====================================================================

create table if not exists departamentos (
    id           serial primary key,
    nombre       text not null unique,
    dane_codigo  text not null unique   -- código DANE de 2 dígitos, ej. '05', '11', '88'
);

create table if not exists ciudades (
    id               serial primary key,
    nombre           text not null,
    departamento_id  int references departamentos(id),
    dane_codigo      text unique,       -- código DIVIPOLA de 5 dígitos, ej. '05001'
    slug             text not null unique
);

create index if not exists idx_ciudades_departamento_id on ciudades (departamento_id);
create index if not exists idx_ciudades_nombre           on ciudades (nombre);

-- ---------------------------------------------------------------------
-- RLS: el contrato no detalla políticas explícitas para estas dos tablas
-- de catálogo (se enfoca en personas/acopios/contadores_cache/
-- rate_limit_log), pero el frontend necesita leerlas para poblar los
-- <select> de ciudad (supabase.from('ciudades').select('id,nombre,
-- departamentos(nombre)')). Se agrega aquí SOLO SELECT público, sin
-- INSERT/UPDATE/DELETE para anon/authenticated — consistente con el
-- principio de "default deny" del resto del contrato. La carga de datos
-- (este seed) se hace con la service role key, nunca desde el cliente.
-- ---------------------------------------------------------------------

alter table departamentos enable row level security;
alter table ciudades      enable row level security;

drop policy if exists departamentos_select_publico on departamentos;
create policy departamentos_select_publico
    on departamentos for select
    to anon, authenticated
    using (true);

drop policy if exists ciudades_select_publico on ciudades;
create policy ciudades_select_publico
    on ciudades for select
    to anon, authenticated
    using (true);

revoke all on departamentos, ciudades from anon, authenticated;
grant select on departamentos to anon, authenticated;
grant select on ciudades      to anon, authenticated;
