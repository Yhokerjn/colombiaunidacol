// supabase/functions/submit-reporte/index.ts
//
// Edge Function: submit-reporte
// Implementa EXACTAMENTE la sección "EDGE FUNCTION submit-reporte" del contrato
// de arquitectura de Colombia Unida.
//
// Deploy:
//   supabase functions deploy submit-reporte
//
// Secrets requeridos (ver bloque de comandos CLI entregado aparte):
//   SUPABASE_SERVICE_ROLE_KEY, IP_SALT, RECAPTCHA_SECRET_KEY, ALLOWED_ORIGIN
//
// Nota: SUPABASE_URL es inyectada automáticamente por el runtime de Supabase
// Edge Functions, no hace falta declararla como secret manual.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Config / entorno
// ---------------------------------------------------------------------------

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_SALT = Deno.env.get("IP_SALT") ?? "";
const RECAPTCHA_SECRET_KEY = Deno.env.get("RECAPTCHA_SECRET_KEY") ?? "";
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") ?? "*";

const RUTA = "submit-reporte";
const RATE_LIMIT_MAX = 3;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hora
const RECAPTCHA_MIN_SCORE = 0.5;

// Cliente con service role: NUNCA se expone al cliente/frontend.
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ---------------------------------------------------------------------------
// Utilidades CORS
// ---------------------------------------------------------------------------

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}

// ---------------------------------------------------------------------------
// Sanitización de campos de texto (defensa en profundidad; el trigger de DB
// vuelve a validar todo esto server-side en Postgres).
// ---------------------------------------------------------------------------

const FORBIDDEN_PATTERNS: RegExp[] = [
  /<script/i,
  /javascript:/i,
  /<iframe/i,
  /--/,
  /;--/,
  /\/\*/,
  /xp_/i,
  /union\s+select/i,
  /drop\s+table/i,
];

class ValidationError extends Error {}

function containsForbidden(value: string): boolean {
  return FORBIDDEN_PATTERNS.some((re) => re.test(value));
}

/** Trim + validación de longitud + validación de patrones peligrosos. */
function sanitizeRequiredText(
  raw: unknown,
  field: string,
  { min = 3, max }: { min?: number; max: number },
): string {
  if (typeof raw !== "string") {
    throw new ValidationError(`El campo '${field}' es requerido y debe ser texto.`);
  }
  const trimmed = raw.trim();
  if (trimmed.length < min) {
    throw new ValidationError(`El campo '${field}' debe tener al menos ${min} caracteres.`);
  }
  if (trimmed.length > max) {
    throw new ValidationError(`El campo '${field}' excede la longitud máxima de ${max} caracteres.`);
  }
  if (containsForbidden(trimmed)) {
    throw new ValidationError(`El campo '${field}' contiene contenido no permitido.`);
  }
  return trimmed;
}

/** Igual que sanitizeRequiredText pero el campo puede venir vacío / null / undefined. */
function sanitizeOptionalText(raw: unknown, field: string, max: number): string | null {
  if (raw === null || raw === undefined || raw === "") return null;
  if (typeof raw !== "string") {
    throw new ValidationError(`El campo '${field}' debe ser texto.`);
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > max) {
    throw new ValidationError(`El campo '${field}' excede la longitud máxima de ${max} caracteres.`);
  }
  if (containsForbidden(trimmed)) {
    throw new ValidationError(`El campo '${field}' contiene contenido no permitido.`);
  }
  return trimmed;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getClientIp(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip");
  if (cf) return cf;
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return "unknown";
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface RecaptchaVerifyResult {
  success: boolean;
  score?: number;
  action?: string;
  "error-codes"?: string[];
}

async function verifyRecaptcha(token: string, remoteIp: string): Promise<RecaptchaVerifyResult> {
  const params = new URLSearchParams();
  params.set("secret", RECAPTCHA_SECRET_KEY);
  params.set("response", token);
  if (remoteIp && remoteIp !== "unknown") {
    params.set("remoteip", remoteIp);
  }

  const res = await fetch("https://www.google.com/recaptcha/api/siteverify", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  return (await res.json()) as RecaptchaVerifyResult;
}

interface SubmitReportePayload {
  nombres: string;
  apellidos: string;
  estado: "desaparecido" | "localizado";
  ciudad_id: number;
  ciudad_nombre: string;
  ubicacion: string;
  descripcion: string | null;
  contacto: string;
  foto_url: string | null;
  recaptchaToken: string;
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  // Preflight CORS
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // ---- Parseo de body ----
  let rawBody: Record<string, unknown>;
  try {
    rawBody = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  // ---- Paso 1: IP real ----
  const ip = getClientIp(req);

  // ---- Paso 2: ip_hash ----
  const ip_hash = await sha256Hex(ip + IP_SALT);

  // ---- Validación básica de estado / recaptchaToken antes de llamar a Google ----
  const recaptchaToken = rawBody?.recaptchaToken;
  if (typeof recaptchaToken !== "string" || recaptchaToken.length === 0) {
    return jsonResponse({ error: "recaptcha_token_faltante" }, 400);
  }

  const estadoRaw = rawBody?.estado;
  if (estadoRaw !== "desaparecido" && estadoRaw !== "localizado") {
    return jsonResponse({ error: "estado_invalido" }, 400);
  }

  // ---- Paso 3: Verificación reCAPTCHA v3 ----
  try {
    const verification = await verifyRecaptcha(recaptchaToken, ip);
    if (!verification.success || (verification.score ?? 0) < RECAPTCHA_MIN_SCORE) {
      return jsonResponse({ error: "bot_sospechoso" }, 403);
    }
  } catch {
    return jsonResponse({ error: "bot_sospechoso" }, 403);
  }

  // ---- Paso 4: Rate limit (3 reportes / hora / IP) ----
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString();
  const { count: rateCount, error: rateError } = await supabaseAdmin
    .from("rate_limit_log")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ip_hash)
    .eq("ruta", RUTA)
    .gte("created_at", windowStart);

  if (rateError) {
    return jsonResponse({ error: "error_interno", detalle: rateError.message }, 500);
  }

  if ((rateCount ?? 0) >= RATE_LIMIT_MAX) {
    return jsonResponse(
      {
        error: "rate_limited",
        mensaje: "Has alcanzado el límite de 3 reportes por hora. Intenta más tarde.",
      },
      429,
    );
  }

  // ---- Paso 5: Sanitizar/trim todos los campos de texto ----
  let payload: SubmitReportePayload;
  try {
    const nombres = sanitizeRequiredText(rawBody?.nombres, "nombres", { max: 100 });
    const apellidos = sanitizeRequiredText(rawBody?.apellidos, "apellidos", { max: 100 });
    const ubicacion = sanitizeRequiredText(rawBody?.ubicacion, "ubicacion", { max: 300 });
    const contacto = sanitizeRequiredText(rawBody?.contacto, "contacto", { max: 20 });
    const ciudad_nombre = sanitizeRequiredText(rawBody?.ciudad_nombre, "ciudad_nombre", { max: 100 });
    const descripcion = sanitizeOptionalText(rawBody?.descripcion, "descripcion", 1000);
    const foto_url = sanitizeOptionalText(rawBody?.foto_url, "foto_url", 2048);

    const ciudad_id_raw = rawBody?.ciudad_id;
    const ciudad_id = typeof ciudad_id_raw === "number" ? ciudad_id_raw : Number(ciudad_id_raw);
    if (!Number.isInteger(ciudad_id) || ciudad_id <= 0) {
      throw new ValidationError("El campo 'ciudad_id' es requerido y debe ser un entero válido.");
    }

    payload = {
      nombres,
      apellidos,
      estado: estadoRaw,
      ciudad_id,
      ciudad_nombre,
      ubicacion,
      descripcion,
      contacto,
      foto_url,
      recaptchaToken,
    };
  } catch (err) {
    if (err instanceof ValidationError) {
      return jsonResponse({ error: "validacion_fallida", mensaje: err.message }, 400);
    }
    return jsonResponse({ error: "error_interno" }, 500);
  }

  // ---- Paso 6: Buscar duplicado ----
  const { data: dupData, error: dupError } = await supabaseAdmin.rpc("buscar_duplicado_persona", {
    p_nombres: payload.nombres,
    p_apellidos: payload.apellidos,
  });

  if (dupError) {
    return jsonResponse({ error: "error_interno", detalle: dupError.message }, 500);
  }

  const duplicado = Array.isArray(dupData) ? dupData[0] : dupData;

  if (duplicado?.encontrado === true) {
    if (duplicado.estado === "desaparecido") {
      return jsonResponse(
        {
          duplicado: true,
          tipo: "desaparecido",
          mensaje: `Esta persona ya fue reportada como desaparecida en ${duplicado.ciudad_nombre}, ${duplicado.ubicacion}.`,
        },
        409,
      );
    }

    if (duplicado.estado === "localizado") {
      return jsonResponse(
        {
          duplicado: true,
          tipo: "localizado",
          mensaje: `¡ATENCIÓN! Alguien ya publicó a esta persona y se encuentra LOCALIZADA A SALVO en ${duplicado.ciudad_nombre}, ${duplicado.ubicacion}.`,
        },
        409,
      );
    }
  }

  // ---- Paso 7: Insertar persona (tabla pública, sin PII) ----
  // `contacto` e `ip_hash` NO viven en `personas`: esa tabla se transmite por
  // Realtime a cualquier cliente anon suscrito (telemetría en vivo), y el
  // payload de Realtime viaja por WAL, no por PostgREST — no hay garantía de
  // que respete los mismos privilegios de columna que una consulta REST. Por
  // eso el teléfono del reportante va en `personas_contacto`, una tabla que
  // nunca se agrega a la publicación de Realtime ni recibe grants para anon.
  const { data: inserted, error: insertError } = await supabaseAdmin
    .from("personas")
    .insert({
      nombres: payload.nombres,
      apellidos: payload.apellidos,
      estado: payload.estado,
      ciudad_id: payload.ciudad_id,
      ciudad_nombre: payload.ciudad_nombre,
      ubicacion: payload.ubicacion,
      descripcion: payload.descripcion,
      foto_url: payload.foto_url,
    })
    .select("id")
    .single();

  if (insertError) {
    // 23505 = choque del índice único (lower(nombres), lower(apellidos)):
    // dos requests casi simultáneos pasaron el chequeo de duplicado del Paso 6
    // antes de que cualquiera terminara de insertar. Se responde igual que un
    // duplicado detectado normalmente, en vez de un error genérico 500.
    if (insertError.code === "23505") {
      return jsonResponse(
        {
          duplicado: true,
          tipo: "concurrente",
          mensaje: "Esta persona acaba de ser registrada por otro reporte. Verifique la base de datos antes de reintentar.",
        },
        409,
      );
    }
    return jsonResponse({ error: "error_interno", detalle: insertError.message }, 500);
  }

  const { error: contactoError } = await supabaseAdmin.from("personas_contacto").insert({
    persona_id: inserted.id,
    contacto: payload.contacto,
    ip_hash,
  });

  if (contactoError) {
    // El reporte público ya se guardó; no revertimos la fila de `personas`
    // por un fallo al guardar el contacto, pero sí lo registramos para
    // investigar (sin el contacto, nadie puede avisarle al reportante).
    console.error("Error insertando personas_contacto:", contactoError.message);
  }

  const { error: logError } = await supabaseAdmin.from("rate_limit_log").insert({
    ip_hash,
    ruta: RUTA,
  });

  if (logError) {
    // El reporte ya se guardó correctamente; el fallo del log no debe
    // impedir la respuesta de éxito al usuario, pero sí lo registramos.
    console.error("Error insertando rate_limit_log:", logError.message);
  }

  return jsonResponse({ success: true, id: inserted.id }, 201);
});
