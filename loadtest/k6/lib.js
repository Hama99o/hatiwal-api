// Shared helpers for the Hatiwal load test (docs/LOAD_TEST.md).
import http from "k6/http";
import { check } from "k6";
import { SharedArray } from "k6/data";

export const BASE = __ENV.BASE_URL || "http://loadtest-api";
export const API = `${BASE}/api/v1`;

// Auth headers prepared by loadtest/seed.rb (nobody signs in during a run:
// sign_in is throttled to 20 per 5 minutes per IP, and k6 is one IP).
export const TOKENS = new SharedArray("tokens", () => JSON.parse(open(__ENV.TOKENS || "/tokens/tokens.json")));
const META = new SharedArray("meta", () => [JSON.parse(open(__ENV.META || "/tokens/meta.json"))]);
export const meta = () => META[0];

export const pick = (a) => a[Math.floor(Math.random() * a.length)];

// One user per VU, so per-user throttles (messages 120/h, publish 30/day…)
// see a realistic spread instead of one hot account.
export function authFor(vu) {
  const t = TOKENS[(vu - 1) % TOKENS.length];
  return { "access-token": t["access-token"], client: t.client, uid: t.uid, "token-type": "Bearer",
           "Content-Type": "application/json", "X-App-Version": "1.1.6", "X-App-Platform": "android" };
}

export function get(path, headers, name) {
  const r = http.get(path.startsWith("http") ? path : `${API}${path}`, { headers, tags: { name } });
  check(r, { [`${name} 2xx`]: (x) => x.status >= 200 && x.status < 300 });
  return r;
}

export function json(r) {
  try { return r.json(); } catch (_) { return null; }
}

// A Rails representation URL (thumb / medium): the FIRST request generates the
// variant (libvips, inside the request) and redirects; later ones only redirect.
// `phase` tags first-generation vs cached so the two are reported apart.
export function variant(url, phase) {
  // Production builds absolute urls on its public host; send them to the test API.
  const r = http.get(url.replace(/^https?:\/\/[^/]+/, BASE), { redirects: 0, tags: { name: `variant_${phase}` } });
  check(r, { [`variant_${phase} 302`]: (x) => x.status === 302 });
  return r;
}

// ramp 10 → 500 VUs (the planned shape; override with STAGES='[…]').
export const RAMP = __ENV.STAGES ? JSON.parse(__ENV.STAGES) : [
  { duration: "1m", target: 10 },
  { duration: "3m", target: 100 },
  { duration: "3m", target: 250 },
  { duration: "3m", target: 500 },
  { duration: "3m", target: 500 },
  { duration: "1m", target: 0 },
];

export const THRESHOLDS = {
  http_req_failed: ["rate<0.01"],
  "http_req_duration{name:browse}": ["p(95)<800"],
  "http_req_duration{name:listing}": ["p(95)<800"],
  "http_req_duration{name:me}": ["p(95)<500"],
};
