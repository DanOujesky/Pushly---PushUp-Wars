// push-send: delivers due rows of push_outbox (doc 12, roadmap P6-05). Called every minute by pg_cron (service role).
import { json } from "../_shared/http.ts";
import { render } from "./messages.ts";
import type { Outcome } from "./providers.ts";

export interface Device {
  id: string;
  platform: "ios" | "android";
  token: string;
}

export interface Job {
  id: number;
  userId: string;
  type: string;
  category: string;
  payload: Record<string, unknown>;
  silent: boolean;
  collapseKey: string | null;
  devices: Device[];
}

export interface Result {
  id: number;
  ok: boolean;
  error?: string;
  retry?: boolean;
}

export interface Deps {
  isServiceRole: (authorization: string) => boolean;
  claim: (limit: number) => Promise<Job[]>;
  finish: (results: Result[], deadDevices: string[]) => Promise<void>;
  /** null = that provider isn't configured yet (secrets missing). */
  sendIos: ((job: Job, device: Device) => Promise<Outcome>) | null;
  sendAndroid: ((job: Job, device: Device) => Promise<Outcome>) | null;
}

export async function deliver(jobs: Job[], deps: Deps): Promise<{ results: Result[]; dead: string[] }> {
  const results: Result[] = [];
  const dead: string[] = [];
  for (const job of jobs) {
    if (!render(job.type, job.payload)) {
      results.push({ id: job.id, ok: false, error: `unknown type ${job.type}`, retry: false });
      continue;
    }
    if (job.devices.length === 0) {
      results.push({ id: job.id, ok: false, error: "no_device", retry: false });
      continue;
    }
    let delivered = false;
    let retry = false;
    const errors: string[] = [];
    for (const device of job.devices) {
      const send = device.platform === "ios" ? deps.sendIos : deps.sendAndroid;
      if (!send) {
        errors.push(`${device.platform}_not_configured`);
        continue;
      }
      const out = await send(job, device);
      if (out.ok) {
        delivered = true;
      } else {
        errors.push(out.error);
        if (out.dead) dead.push(device.id);
        if (out.retry) retry = true;
      }
    }
    results.push(delivered ? { id: job.id, ok: true } : { id: job.id, ok: false, error: errors.join("; "), retry });
  }
  return { results, dead };
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!deps.isServiceRole(req.headers.get("authorization") ?? "")) return json({ error: "forbidden" }, 403);
  const jobs = await deps.claim(200);
  const { results, dead } = await deliver(jobs, deps);
  if (results.length > 0 || dead.length > 0) await deps.finish(results, dead);
  return json({ claimed: jobs.length, sent: results.filter((r) => r.ok).length, dead: dead.length });
}
