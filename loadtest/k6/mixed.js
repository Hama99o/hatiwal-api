// The main run: the app's real mix, ramped 10 → 500 VUs (docs/LOAD_TEST.md).
// Each VU is one signed-in person who, per iteration, does one of:
//   browse (Bazaar feed + search + near me)   50 %
//   open a listing (+ its thumbs)             25 %
//   chat (inbox, a thread, send, read)        15 %
//   poll /users/me (the 60 s unread poll)     always, once per iteration
//   publish a listing with 3 photos           SCENARIO=publish adds it (see publish.js)
import { sleep } from "k6";
import { authFor, RAMP, THRESHOLDS } from "./lib.js";
import { browse, openListing, chat, pollMe } from "./flows.js";

export const options = {
  scenarios: { mixed: { executor: "ramping-vus", startVUs: 0, stages: RAMP, gracefulRampDown: "30s" } },
  thresholds: THRESHOLDS,
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export default function () {
  const h = authFor(__VU);
  const r = Math.random();
  if (r < 0.5) browse(h);
  else if (r < 0.75) openListing(h);
  else chat(h);
  pollMe(h);
  sleep(2 + Math.random() * 4); // think time: a person reading the screen
}

export function handleSummary(data) {
  return { "/results/mixed-summary.json": JSON.stringify(data, null, 2) };
}
