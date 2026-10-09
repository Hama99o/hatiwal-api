// Photo variants: FIRST generation vs CACHED (docs/LOAD_TEST.md).
// Phase 1 "first": every blob's thumb is requested once (shared iterations over
// the listings, at most LT_COLD_VUS at a time). Each request generates a WebP
// with libvips inside a Puma thread — this is the cost a burst of new photos
// puts on the box. Phase 2 "cached": the same urls again, now only a lookup +
// redirect. Run it on a FRESH seed (no variant generated yet), before mixed.js.
import exec from "k6/execution";
import { authFor, get, json, meta, variant } from "./lib.js";

const LISTINGS = Number(__ENV.LT_COLD_LISTINGS || 1500);
const COLD_VUS = Number(__ENV.LT_COLD_VUS || 20);

export const options = {
  scenarios: {
    first: { executor: "shared-iterations", vus: COLD_VUS, iterations: LISTINGS, maxDuration: "20m",
             env: { PHASE: "first" } },
    cached: { executor: "constant-vus", vus: COLD_VUS, duration: "3m", startTime: "21m", env: { PHASE: "cached" } },
  },
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export default function () {
  const ids = meta().listing_ids;
  // first: each listing exactly once across all VUs; cached: random among the same ones.
  const id = __ENV.PHASE === "first"
    ? ids[exec.scenario.iterationInTest % ids.length]
    : ids[Math.floor(Math.random() * Math.min(LISTINGS, ids.length))];
  const l = (json(get(`/listings/${id}`, authFor(__VU), "listing")) || {}).listing || {};
  (l.image_thumb_urls || []).forEach((u) => variant(u, __ENV.PHASE));
  if ((l.image_medium_urls || [])[0]) variant(l.image_medium_urls[0], __ENV.PHASE);
}

export function handleSummary(data) {
  return { "/results/variants-summary.json": JSON.stringify(data, null, 2) };
}
