import { handler } from "./handler.ts";

// Secret: REVENUECAT_WEBHOOK_AUTH = the exact Authorization header value set in RevenueCat → Integrations → Webhooks.
const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function apply(event: Record<string, unknown>): Promise<string> {
  const res = await fetch(`${url}/rest/v1/rpc/apply_entitlement_event`, {
    method: "POST",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ e: event }),
  });
  if (!res.ok) throw new Error(`apply_entitlement_event ${res.status} ${await res.text()}`);
  return String(await res.json());
}

Deno.serve((req) => handler(req, { secret: Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? null, apply }));
