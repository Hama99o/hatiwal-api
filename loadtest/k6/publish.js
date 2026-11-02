// Publish with 3 photos (docs/LOAD_TEST.md): POST /my/listings as multipart
// (title, price, category, pin, listing[images][] ×3), then
// PUT /my/listings/:id/publish — the path the app takes.
// The per-user limit is 30 creates a day, so each iteration posts as the next
// user in TOKENS (LT_TOKEN_USERS of them). A low, steady arrival rate on
// purpose: sellers post far less often than buyers browse.
import http from "k6/http";
import { check } from "k6";
import exec from "k6/execution";
import { API, TOKENS, meta, pick } from "./lib.js";

const PHOTO = open("/tokens/photo.jpg", "b"); // a real 1280 px seed photo, copied there by run.sh

export const options = {
  scenarios: {
    publish: { executor: "constant-arrival-rate", rate: Number(__ENV.PUBLISH_PER_MIN || 30), timeUnit: "1m",
               duration: __ENV.PUBLISH_DURATION || "10m", preAllocatedVUs: 10, maxVUs: 50 },
  },
  thresholds: {
    "http_req_duration{name:create_3_photos}": ["p(95)<3000"],
    "http_req_duration{name:publish}": ["p(95)<1000"],
  },
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

// k6 cannot repeat a multipart key from an object body (listing[images][] ×3),
// so the body is built by hand. Field values are ASCII.
function multipart(fields, files) {
  const boundary = `----hatiwal-loadtest-${Date.now()}`;
  const ascii = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0));
  const parts = [];
  for (const [k, v] of fields) {
    parts.push(ascii(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`));
  }
  for (const [k, name, data] of files) {
    parts.push(ascii(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"; filename="${name}"\r\nContent-Type: image/jpeg\r\n\r\n`));
    parts.push(new Uint8Array(data));
    parts.push(ascii("\r\n"));
  }
  parts.push(ascii(`--${boundary}--\r\n`));
  const body = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { body.set(p, o); o += p.length; }
  return { body: body.buffer, contentType: `multipart/form-data; boundary=${boundary}` };
}

export default function () {
  const n = exec.scenario.iterationInTest;
  const t = TOKENS[n % TOKENS.length];
  const auth = { "access-token": t["access-token"], client: t.client, uid: t.uid, "token-type": "Bearer" };
  const p = pick(meta().places);
  const { body, contentType } = multipart(
    [
      ["listing[title]", `Load test sofa ${n}`],
      ["listing[description]", "Posted by the load test."],
      ["listing[price]", "15000"], ["listing[currency]", "AFN"], ["listing[condition]", "good"],
      ["listing[category_id]", String(pick(meta().category_ids))],
      ["listing[location]", "Kabul, Kabul"],
      ["listing[latitude]", String(p.lat)], ["listing[longitude]", String(p.lng)],
    ],
    [1, 2, 3].map((i) => ["listing[images][]", `photo-${i}.jpg`, PHOTO]),
  );
  const created = http.post(`${API}/my/listings`, body,
    { headers: { ...auth, "Content-Type": contentType }, tags: { name: "create_3_photos" } });
  check(created, { "create 201": (r) => r.status === 201, "create not throttled": (r) => r.status !== 429 });
  const id = created.status === 201 ? created.json("listing.id") : null;
  if (!id) return;
  const pub = http.put(`${API}/my/listings/${id}/publish`, null, { headers: auth, tags: { name: "publish" } });
  check(pub, { "publish 200": (r) => r.status === 200 });
}

export function handleSummary(data) {
  return { "/results/publish-summary.json": JSON.stringify(data, null, 2) };
}
