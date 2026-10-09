// Chat over ActionCable (docs/LOAD_TEST.md): 10 → 500 open WebSockets, each
// subscribed to one of its user's conversations (ConversationChannel), held
// open like an app sitting on a thread. One VU in five also sends a message
// over HTTP every ~20 s and measures how long until it comes back on its own
// stream (solid_cable polls every 0.1 s in production) — the chat's real latency.
import http from "k6/http";
import ws from "k6/ws";
import { check } from "k6";
import { Counter, Trend } from "k6/metrics";
import { API, BASE, RAMP, authFor, json } from "./lib.js";

const subscribed = Counter("cable_subscribed");
const rejected = Counter("cable_rejected");
const delivery = Trend("cable_delivery_ms", true);
const HOLD_MS = Number(__ENV.CABLE_HOLD_MS || 60000);
const WS = BASE.replace(/^http/, "ws");

export const options = {
  scenarios: { cable: { executor: "ramping-vus", startVUs: 0, stages: RAMP, gracefulRampDown: "70s" } },
  thresholds: { cable_delivery_ms: ["p(95)<2000"], cable_rejected: ["count<1"] },
  summaryTrendStats: ["avg", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export default function () {
  const h = authFor(__VU);
  const convo = ((json(http.get(`${API}/conversations?page=1`, { headers: h, tags: { name: "inbox" } })) || {})
    .conversations || [])[0];
  if (!convo) return;
  const identifier = JSON.stringify({ channel: "ConversationChannel", conversation_id: convo.id });
  const url = `${WS}/hatiwal-cable?access_token=${encodeURIComponent(h["access-token"])}` +
              `&client=${encodeURIComponent(h.client)}&uid=${encodeURIComponent(h.uid)}`;
  const sender = __VU % 5 === 0;
  const pending = {};

  const res = ws.connect(url, { headers: { Origin: "http://loadtest.invalid" }, tags: { name: "cable" } }, (socket) => {
    socket.on("open", () => socket.send(JSON.stringify({ command: "subscribe", identifier })));
    socket.on("message", (raw) => {
      const m = JSON.parse(raw);
      if (m.type === "confirm_subscription") subscribed.add(1);
      else if (m.type === "reject_subscription") rejected.add(1);
      else if (m.message) {
        const body = JSON.stringify(m.message);
        for (const tag of Object.keys(pending)) {
          if (body.includes(tag)) { delivery.add(Date.now() - pending[tag]); delete pending[tag]; }
        }
      }
    });
    if (sender) {
      socket.setInterval(() => {
        const tag = `lt-${__VU}-${Date.now()}`;
        pending[tag] = Date.now();
        http.post(`${API}/conversations/${convo.id}/messages`, JSON.stringify({ body: `cable ${tag}` }),
                  { headers: h, tags: { name: "send" } });
      }, 20000 + Math.random() * 5000);
    }
    socket.setTimeout(() => socket.close(), HOLD_MS);
  });
  check(res, { "cable 101": (r) => r && r.status === 101 });
}

export function handleSummary(data) {
  return { "/results/cable-summary.json": JSON.stringify(data, null, 2) };
}
