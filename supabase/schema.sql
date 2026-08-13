-- =====================================================================
-- ColombiaUnida — Esquema de Base de Datos (Supabase / Postgres)
-- CONTRATO DE ARQUITECTURA v2
-- =====================================================================
-- Este archivo define personas, acopios, rate_limit_log, la vista
-- pública y el RPC de duplicados. DEPENDE de que ya se haya ejecutado
-- 00_departamentos_ciudades_ddl.sql (crea `departamentos` y `ciudades`)
-- y su seed (seed_ciudades.sql).
--
-- Orden de ejecución en Supabase Dashboard > SQL Editor:
--   1) 00_departamentos_ciudades_ddl.sql
--   2) seed_ciudades.sql
--   3) schema.sql (este archivo)
--
-- DECISIÓN DE DISEÑO — por qué `contacto` vive en una tabla separada:
-- El Edge Function `submit-reporte` es el único camino de escritura a
-- `personas` (usa la service_role key, RLS no le aplica). Eso permite
-- exponer `personas` en Realtime (Misión #4: telemetría en vivo) de
-- forma segura SIEMPRE QUE la tabla no contenga PII — Supabase Realtime
-- transmite el payload completo de la fila por WebSocket a cualquier
-- cliente suscrito, y esa transmisión ocurre a nivel de replicación
-- (WAL), no a través de PostgREST. Los privilegios de columna
-- (`grant select (columnas...)`) sí protegen las consultas REST/RPC,
-- pero no hay garantía documentada de que también filtren el payload
-- de Realtime. Por eso el teléfono de contacto del reportante
-- (`contacto`) y el hash de IP (`ip_hash`) se guardan en
-- `personas_contacto`, una tabla que NUNCA se agrega a la publicación
-- de Realtime y que no tiene ningún grant para anon/authenticated.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. TABLAS
-- ---------------------------------------------------------------------

-- Tabla pública: cero PII. Segura para exponer vía SELECT directo y Realtime.
create table if not exists personas (
    id            uuid primary key default gen_random_uuid(),
    estado        text not null check (estado in ('desaparecido', 'localizado')),
    nombres       text not null,
    apellidos     text not null,
    ciudad_id     int references ciudades(id),
    ciudad_nombre text not null,
    ubicacion     text not null,
    descripcion   text,
    foto_url      text,
    tipo_refugio  text check (tipo_refugio in ('albergue', 'hospital')),
    created_at    timestamptz not null default now()
);

create index if not exists idx_personas_ciudad_nombre on personas (ciudad_nombre);
create index if not exists idx_personas_estado on personas (estado);

-- Backstop de concurrencia (Misión #3): si dos requests casi simultáneos
-- pasan la verificación de duplicados del Edge Function antes de que
-- cualquiera termine de insertar, este índice único garantiza que solo
-- uno gane. El Edge Function debe traducir el error 23505 resultante
-- al mismo mensaje de "ya existe" (ver nota en submit-reporte/index.ts).
create unique index if not exists idx_personas_nombre_unico on personas (lower(nombres), lower(apellidos));

-- Tabla privada: PII del reportante. Solo la toca el Edge Function
-- (service_role). Jamás se agrega a supabase_realtime ni recibe grants.
create table if not exists personas_contacto (
    persona_id uuid primary key references personas(id) on delete cascade,
    contacto   text not null,
    ip_hash    text,
    created_at timestamptz not null default now()
);

create table if not exists acopios (
    id            uuid primary key default gen_random_uuid(),
    nombre        text not null,
    ciudad_nombre text not null,
    direccion     text not null,
    estado        text not null check (estado in ('Abierto', 'Saturado', 'Cerrado')),
    necesidades   text[] not null default '{}',
    horario       text,
    created_at    timestamptz not null default now()
);

create index if not exists idx_acopios_ciudad_nombre on acopios (ciudad_nombre);

-- Bitácora de Rate Limiting (Misión #5). Solo la lee/escribe el Edge
-- Function con la service_role key. `ruta` permite reusar la tabla
-- para futuros endpoints sin mezclar sus contadores.
create table if not exists rate_limit_log (
    id         bigserial primary key,
    ip_hash    text not null,
    ruta       text not null,
    created_at timestamptz not null default now()
);

create index if not exists idx_rate_limit_log_ip_ruta_tiempo on rate_limit_log (ip_hash, ruta, created_at);

-- ---------------------------------------------------------------------
-- 2. RPC: búsqueda de duplicados (Misión #3)
--    La llama el Edge Function con la service_role key (bypassa RLS),
--    así que no necesita SECURITY DEFINER ni grants para anon.
-- ---------------------------------------------------------------------

create or replace function buscar_duplicado_persona(p_nombres text, p_apellidos text)
returns table(encontrado boolean, estado text, ciudad_nombre text, ubicacion text)
language sql
stable
as $$
    select true, p.estado, p.ciudad_nombre, p.ubicacion
    from personas p
    where lower(p.nombres) = lower(p_nombres)
      and lower(p.apellidos) = lower(p_apellidos)
    limit 1;
$$;

-- ---------------------------------------------------------------------
-- 3. Auto-inferencia de tipo_refugio (filtro "Tipo de Refugio" en
--    localizados.html). El formulario público no pide este dato de
--    forma explícita, así que se infiere por palabras clave en
--    ubicación/descripción antes de insertar.
-- ---------------------------------------------------------------------

create or replace function fn_inferir_tipo_refugio()
returns trigger
language plpgsql
as $$
begin
    if NEW.tipo_refugio is null then
        if (coalesce(NEW.ubicacion, '') || ' ' || coalesce(NEW.descripcion, ''))
           ~* '(hospital|cl[íi]nica|urgencias|centro m[ée]dico|\bips\b)'
        then
            NEW.tipo_refugio := 'hospital';
        else
            NEW.tipo_refugio := 'albergue';
        end if;
    end if;
    return NEW;
end;
$$;

drop trigger if exists trg_inferir_tipo_refugio on personas;
create trigger trg_inferir_tipo_refugio
    before insert on personas
    for each row
    execute function fn_inferir_tipo_refugio();

-- ---------------------------------------------------------------------
-- 4. Vista pública (nombre_completo + search_vector para
--    localizados.html, que ya está escrito contra v_personas_publico)
-- ---------------------------------------------------------------------

create or replace view v_personas_publico as
select
    id,
    nombres,
    apellidos,
    (nombres || ' ' || apellidos) as nombre_completo,
    estado,
    ciudad_nombre,
    ubicacion,
    descripcion,
    foto_url,
    tipo_refugio,
    created_at,
    to_tsvector(
        'spanish',
        nombres || ' ' || apellidos || ' ' || coalesce(ubicacion, '') || ' ' || coalesce(descripcion, '')
    ) as search_vector
from personas;

-- ---------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY
--    El único camino de escritura a `personas`/`personas_contacto` es
--    el Edge Function submit-reporte (service_role, bypassa RLS). Por
--    eso anon/authenticated no reciben policy de INSERT: un intento de
--    INSERT directo con la anon key es denegado igual que UPDATE/DELETE.
-- ---------------------------------------------------------------------

alter table personas          enable row level security;
alter table personas_contacto enable row level security;
alter table acopios            enable row level security;
alter table rate_limit_log     enable row level security;

drop policy if exists personas_select_publico on personas;
create policy personas_select_publico
    on personas for select
    to anon, authenticated
    using (true);

revoke all on personas from anon, authenticated;
grant select on personas to anon, authenticated;
grant select on v_personas_publico to anon, authenticated;

-- personas_contacto: CERO policies y CERO grants para anon/authenticated.
-- No se agrega a supabase_realtime (ver nota de diseño al inicio del archivo).

drop policy if exists acopios_select_publico on acopios;
create policy acopios_select_publico
    on acopios for select
    to anon, authenticated
    using (true);

revoke all on acopios from anon, authenticated;
grant select on acopios to anon, authenticated;

-- rate_limit_log: cero grants para anon/authenticated. Nunca se expone.

-- ---------------------------------------------------------------------
-- 6. REALTIME (Misión #4) — solo tablas sin PII.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table personas;
alter publication supabase_realtime add table acopios;

-- Nota: si el proyecto ya tiene Realtime activado por Dashboard (Database >
-- Replication), estas líneas pueden fallar con "already member of publication";
-- en ese caso ya está listo y puedes ignorar el error.
