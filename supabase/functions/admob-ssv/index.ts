import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/std@0.224.0/hmac/mod.ts";

/**
 * AdMob Server-Side Verification (SSV) callback endpoint.
 *
 * Google calls this with query parameters:
 *   - user_id: the app's user identifier (our auth.uid())
 *   - custom_data: JSON string we set when loading the ad; contains reward_id
 *   - reward_amount: number
 *   - reward_item: string
 *   - signature: base64 HMAC-SHA256 of the query string (excluding signature param)
 *   - key_id: the key identifier for the public key
 *   - timestamp: milliseconds since epoch
 *
 * In fake mode (ADMOB_FAKE=true, the default until real AdMob IDs are wired):
 *   - We verify the HMAC against a dev-provided fake secret (ADMOB_FAKE_SECRET).
 *   - Real signature verification is scaffolded but skipped with a loud log line.
 *
 * On successful verification, we call the database function ad_reward(user_id, reward_id, ssv_event_id)
 * which grants the reward idempotently on ssv_event_id (the timestamp serves as the event id).
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMOB_FAKE = Deno.env.get("ADMOB_FAKE") !== "false"; // default true
const ADMOB_FAKE_SECRET = Deno.env.get("ADMOB_FAKE_SECRET") || "dev-fake-secret-change-me";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function parseCustomData(customData: string): { reward_id?: string } {
  try {
    return JSON.parse(customData);
  } catch {
    return {};
  }
}

function buildQueryStringForVerification(params: URLSearchParams): string {
  // Google's SSV signature covers all params EXCEPT the signature param itself,
  // sorted by key, joined by '&'.
  const entries: [string, string][] = [];
  for (const [k, v] of params.entries()) {
    if (k !== "signature") {
      entries.push([k, v]);
    }
  }
  entries.sort((a, b) => a[0].localeCompare(b[0]));
  return entries.map(([k, v]) => `${k}=${v}`).join("&");
}

async function verifyFakeSignature(queryString: string, signatureB64: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(ADMOB_FAKE_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const sigBytes = Uint8Array.from(atob(signatureB64), (c) => c.charCodeAt(0));
  return crypto.subtle.verify("HMAC", key, sigBytes, encoder.encode(queryString));
}

async function verifyRealSignature(_queryString: string, _signatureB64: string, _keyId: string): Promise<boolean> {
  // TODO: Implement real AdMob public key fetch and verification.
  // For now, this is a scaffold. In fake mode we never reach here.
  console.warn("[admob-ssv] REAL MODE: signature verification NOT IMPLEMENTED. This should not run in production without real keys.");
  return false;
}

serve(async (req: Request) => {
  const url = new URL(req.url);
  const params = url.searchParams;

  // Required parameters from AdMob SSV
  const userId = params.get("user_id");
  const customData = params.get("custom_data");
  const signature = params.get("signature");
  const keyId = params.get("key_id");
  const timestamp = params.get("timestamp");

  if (!userId || !customData || !signature || !keyId || !timestamp) {
    console.warn("[admob-ssv] Missing required SSV parameters", Object.fromEntries(params));
    return new Response("Missing parameters", { status: 400 });
  }

  const { reward_id } = parseCustomData(customData);
  if (!reward_id) {
    console.warn("[admob-ssv] No reward_id in custom_data", customData);
    return new Response("Invalid custom_data", { status: 400 });
  }

  // The SSV event id is the timestamp (milliseconds since epoch).
  // AdMob guarantees uniqueness per callback.
  const ssvEventId = `ssv_${timestamp}`;

  // Build the query string that was signed (all params except signature, sorted).
  const queryString = buildQueryStringForVerification(params);

  let verified = false;

  if (ADMOB_FAKE) {
    // Fake mode: verify against our dev secret.
    verified = await verifyFakeSignature(queryString, signature);
    if (!verified) {
      console.warn("[admob-ssv] FAKE MODE: HMAC verification FAILED", { userId, reward_id, ssvEventId });
      return new Response("Invalid signature", { status: 403 });
    }
    console.log("[admob-ssv] FAKE MODE: HMAC verified OK", { userId, reward_id, ssvEventId });
  } else {
    // Real mode: verify against AdMob's public key.
    console.warn("[admob-ssv] REAL MODE: using scaffolded verification (NOT SECURE FOR PRODUCTION)");
    verified = await verifyRealSignature(queryString, signature, keyId);
    if (!verified) {
      console.warn("[admob-ssv] REAL MODE: signature verification FAILED", { userId, reward_id, ssvEventId });
      return new Response("Invalid signature", { status: 403 });
    }
    console.log("[admob-ssv] REAL MODE: signature verified", { userId, reward_id, ssvEventId });
  }

  // Call the database function to grant the reward.
  // The function is idempotent on ssv_event_id (replayed callbacks grant nothing).
  const { data, error } = await supabase.rpc("ad_reward", {
    p_user_id: userId,
    p_reward_id: reward_id,
    p_ssv_event_id: ssvEventId,
  });

  if (error) {
    console.error("[admob-ssv] ad_reward failed", { userId, reward_id, ssvEventId, error: error.message });
    // Don't expose internal errors to the caller; AdMob expects 2xx for "received".
    // But we log the error for debugging.
    return new Response("Grant failed", { status: 500 });
  }

  const replay = data?.replay === true;
  console.log("[admob-ssv] Grant result", { userId, reward_id, ssvEventId, gems: data?.gems, replay });

  return new Response(JSON.stringify({ ok: true, replay, gems: data?.gems }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});