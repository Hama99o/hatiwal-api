// The user journeys, shared by the scenario files (docs/LOAD_TEST.md).
import http from "k6/http";
import { check } from "k6";
import { API, get, json, meta, pick, variant } from "./lib.js";

// Bazaar: the feed (newest, page 1–3), a search, and "near me" by distance.
export function browse(h) {
  const m = meta();
  get(`/listings?page=${1 + Math.floor(Math.random() * 3)}`, h, "browse");
  get(`/listings?search=${encodeURIComponent(pick(m.search_words))}`, h, "search");
  const p = pick(m.places);
  get(`/listings?sort=nearest&latitude=${p.lat}&longitude=${p.lng}&radius=50`, h, "near");
  if (Math.random() < 0.3) get(`/listings?category_id=${pick(m.category_ids)}`, h, "browse");
}

// A listing's page and the photos the app loads first: its thumbs (cards) and
// the first medium (gallery). Whether a variant is generated or cached depends
// on what ran before; variants.js measures first-generation vs cached cleanly.
export function openListing(h) {
  const r = get(`/listings/${pick(meta().listing_ids)}`, h, "listing");
  const l = (json(r) || {}).listing || {};
  (l.image_thumb_urls || []).slice(0, 2).forEach((u) => variant(u, "mixed"));
  if ((l.image_medium_urls || [])[0]) variant(l.image_medium_urls[0], "mixed");
  get(`/listings/${l.id || pick(meta().listing_ids)}/similar`, h, "similar");
}

// Chat: the inbox, one thread's messages, then (1 in 3) a send, and mark read.
export function chat(h) {
  const inbox = json(get("/conversations?page=1", h, "inbox")) || {};
  const convo = pick(inbox.conversations || [{}]);
  if (!convo.id) return;
  get(`/conversations/${convo.id}/messages?page=1`, h, "thread");
  if (Math.random() < 0.33) {
    const r = http.post(`${API}/conversations/${convo.id}/messages`,
      JSON.stringify({ body: `Load test ${Date.now()}: still available?` }),
      { headers: h, tags: { name: "send" } });
    // 429 = the per-user message throttle (120/h): counted apart, not a failure of the box.
    check(r, { "send 201": (x) => x.status === 201, "send not throttled": (x) => x.status !== 429 });
  }
  http.put(`${API}/conversations/${convo.id}/mark_read`, null, { headers: h, tags: { name: "mark_read" } });
}

// The app's unread poll (useUnreadMessageCount: GET /users/me every 60 s).
export function pollMe(h) {
  get("/users/me", h, "me");
}
