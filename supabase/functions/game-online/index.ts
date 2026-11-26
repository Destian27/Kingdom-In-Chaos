// Supabase Edge Function: privileged manual review gateway for Kingdom in Chaos DTP.
// This endpoint is NOT a battle simulator. PvP/World Boss results must be inspected
// by a trusted reviewer or validated by a real server-side replay verifier before approval.
//
// Required Edge Function secrets:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   KIC_SCORE_REVIEW_KEY                (long random secret; never ship in the APK)
// Optional:
//   KIC_REVIEW_ALLOWED_ORIGINS          (comma-separated origins for a browser admin UI)
//
// Deploy as the existing `game-online` function. Do not enable public client writes
// to rankings, official World Boss scores, or verified PvP results.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_BODY_BYTES = 300_000;
const MAX_NOTE_CHARS = 500;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BASE_HEADERS = {
  "Access-Control-Allow-Headers": "content-type, x-kic-review-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Cache-Control": "no-store",
  "Vary": "Origin",
};

function json(status: number, body: Record<string, unknown>, origin?: string | null): Response {
  const headers: Record<string, string> = {
    ...BASE_HEADERS,
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  };
  if (origin) headers["Access-Control-Allow-Origin"] = origin;
  return new Response(JSON.stringify(body), { status, headers });
}

function allowedOrigin(req: Request): { ok: boolean; origin?: string | null } {
  const origin = req.headers.get("origin");
  // Native Android requests normally have no Origin header; CORS is not an auth control.
  if (!origin) return { ok: true, origin: null };
  const configured = (Deno.env.get("KIC_REVIEW_ALLOWED_ORIGINS") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean);
  // No browser UI is enabled by default. Add exact origins before using a web admin panel.
  if (configured.includes(origin)) return { ok: true, origin };
  return { ok: false, origin: null };
}

function constantTimeEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  const n = Math.max(aa.length, bb.length);
  let diff = aa.length ^ bb.length;
  for (let i = 0; i < n; i++) diff |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

function asObject(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function noteFrom(body: Record<string, unknown>): string {
  const value = typeof body.note === "string" ? body.note.trim() : "";
  return value.slice(0, MAX_NOTE_CHARS);
}

Deno.serve(async (req: Request) => {
  const cors = allowedOrigin(req);
  if (!cors.ok) return json(403, { error: "Origin is not allowed" });

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: {
      ...BASE_HEADERS,
      ...(cors.origin ? { "Access-Control-Allow-Origin": cors.origin } : {}),
    }});
  }

  if (req.method === "GET" && new URL(req.url).pathname.endsWith("/health")) {
    // Deliberately disclose no project URL, key presence, or database internals.
    return json(200, { ok: true, service: "kic-game-online-review" }, cors.origin);
  }
  if (req.method !== "POST") return json(405, { error: "POST required" }, cors.origin);

  const reviewKey = Deno.env.get("KIC_SCORE_REVIEW_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!reviewKey || !supabaseUrl || !serviceRoleKey) {
    return json(503, { error: "Server review secrets are not configured" }, cors.origin);
  }
  const supplied = req.headers.get("x-kic-review-key") ?? "";
  if (!constantTimeEqual(supplied, reviewKey)) {
    return json(401, { error: "Unauthorized" }, cors.origin);
  }

  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return json(413, { error: "Request body is too large" }, cors.origin);
    }
    const parsed: unknown = JSON.parse(raw);
    const object = asObject(parsed);
    if (!object) return json(400, { error: "Expected a JSON object" }, cors.origin);
    body = object;
  } catch {
    return json(400, { error: "Invalid JSON" }, cors.origin);
  }

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "X-Client-Info": "kic-dtp-result-review/2.0" } },
  });

  const action = body.action;
  if (action === "list_pending_world_boss") {
    const { data, error } = await db.from("game_world_boss_score_claims")
      .select("claim_id,cycle_id,user_id,claimed_score,claim_status,submitted_at")
      .eq("claim_status", "pending").order("submitted_at", { ascending: true }).limit(100);
    if (error) {
      console.error("list_pending_world_boss failed", error.code ?? "unknown");
      return json(500, { error: "Could not load pending World Boss claims" }, cors.origin);
    }
    return json(200, { ok: true, claims: data ?? [] }, cors.origin);
  }

  if (action === "list_open_pvp") {
    const { data, error } = await db.from("game_pvp_matches")
      .select("match_id,player_one,player_two,status,result_verified,started_at,ended_at")
      .eq("status", "in_progress").eq("result_verified", false)
      .order("started_at", { ascending: true }).limit(100);
    if (error) {
      console.error("list_open_pvp failed", error.code ?? "unknown");
      return json(500, { error: "Could not load open PvP matches" }, cors.origin);
    }
    return json(200, { ok: true, matches: data ?? [] }, cors.origin);
  }

  const note = noteFrom(body);
  if (note.length < 8) {
    return json(400, { error: "A review note of at least 8 characters is required" }, cors.origin);
  }
  // Explicit confirmation prevents accidental taps; it does not replace actual verification.
  if (body.confirmed_by_human !== true) {
    return json(400, { error: "Set confirmed_by_human=true only after checking the result" }, cors.origin);
  }

  let result;
  if (action === "approve_world_boss" || action === "reject_world_boss") {
    if (!isUuid(body.claim_id)) return json(400, { error: "claim_id must be a UUID" }, cors.origin);
    const approve = action === "approve_world_boss";
    result = await db.rpc("admin_review_world_boss_claim", {
      p_claim_id: body.claim_id,
      p_approve: approve,
      p_review_note: note,
    });
  } else if (action === "approve_pvp") {
    if (!isUuid(body.match_id)) return json(400, { error: "match_id must be a UUID" }, cors.origin);
    const winner = body.winner_user_id;
    if (winner !== null && !isUuid(winner)) {
      return json(400, { error: "winner_user_id must be a participant UUID or null for a draw" }, cors.origin);
    }
    if (body.battle_summary !== undefined && asObject(body.battle_summary) === null) {
      return json(400, { error: "battle_summary must be a JSON object" }, cors.origin);
    }
    const summary = asObject(body.battle_summary) ?? {};
    if (new TextEncoder().encode(JSON.stringify(summary)).byteLength > 200_000) {
      return json(413, { error: "battle_summary is too large" }, cors.origin);
    }
    result = await db.rpc("admin_review_pvp_result", {
      p_match_id: body.match_id,
      p_winner_user_id: winner,
      p_battle_summary: summary,
      p_review_note: note,
    });
  } else {
    return json(400, { error: "Unknown action" }, cors.origin);
  }

  if (result.error) {
    // Keep internal SQL error text out of the public response; retain a safe code for logs.
    console.error("review RPC failed", String(action), result.error.code ?? "unknown");
    return json(409, { error: "Review failed: item may not be pending, may not exist, or may not match the requested result" }, cors.origin);
  }
  return json(200, { ok: true, action, result: result.data }, cors.origin);
});
