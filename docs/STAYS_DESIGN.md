# Stays (hotels, guest houses, B&B) — design note (1.1.7)

Owner, 2026-10-15: *"add a hotel system: a store can be a hotel. Each room has photos, a price
and details, so people can easily search and find a room in a place/city … It goes in 1.1.7."*

Hatiwal stays a **listing marketplace with in-person contact**: no online booking, no calendar,
no payment. A guest finds a room, messages the host, and settles the stay in person or by phone.
That is the whole scope of this note.

## 1. References (Mobbin)

| Screen | Ref | What we take |
|---|---|---|
| Room detail | Airbnb — https://mobbin.com/screens/53d912ff-a3dc-472b-b525-379c327a89e8 | Under the title, ONE facts line: "Room · 1 queen bed · Shared bathroom". |
| Room detail | Airbnb — https://mobbin.com/screens/b7e64cd3-2019-4efd-b6bb-b4b21165b8e3 | "What this place offers": icon + word per amenity, then the map. |
| Room detail | Airbnb — https://mobbin.com/screens/9a3b9090-fe21-405e-8453-52584cd37e62 | Check-in / check-out and guests maximum as short plain lines ("house rules"). |
| Host form | Airbnb — https://mobbin.com/screens/2c302fb8-52ef-42fb-9640-24b15a66f95f | Guests / Beds as − n + steppers, not free text. |
| Filters (phone) | Marriott — https://mobbin.com/screens/57a62345-4c33-4907-87ae-6aa276627359 | "Price per night" range + amenities as checkboxes, one "Show N results" button. |
| Filters (phone) | Expedia — https://mobbin.com/screens/bc533425-3962-4383-8503-60c527ad8e59 | Amenities as icon tiles. |
| Filters (phone) | Google Maps — https://mobbin.com/screens/5ebe6f71-05ca-49f6-9862-bbd694d04e06 | Guests stepper + "Price per night" in one sheet. |
| Results (web) | Booking.com — https://mobbin.com/screens/9da9a2e6-8880-420f-a470-7abcb75b0a94 | "Your budget (per night)" in the sidebar; card shows room type + beds + price/night. |
| Results (web) | Booking.com — https://mobbin.com/screens/a407d9c7-4176-44b8-b6c3-49445d5558ab | Amenity checkboxes (Breakfast, Parking, Private bathroom) as filters. |

## 2. Decisions

### 2.1 Category: a "Stays" tree, marked by a category KIND
- A new top-level category **Stays** (`slug: stays`, icon 🛏️, position just after Property). Its
  children:

| slug | en | ps | fa | ur |
|---|---|---|---|---|
| `stays` | Stays | استوګنځایونه | اقامتگاه | قیام گاہیں |
| `hotel-rooms` | Hotel Rooms | د هوټل کوټې | اتاق هتل | ہوٹل کے کمرے |
| `guest-houses` | Guest Houses | مېلمستونونه | مهمان‌خانه و مسافرخانه | گیسٹ ہاؤس |
| `bed-breakfast` | Bed & Breakfast | کوټه او سهارنی | اتاق با صبحانه | بستر اور ناشتہ |
| `short-stay-apartments` | Short-stay Apartments | لنډمهاله اپارتمانونه | آپارتمان کوتاه‌مدت | مختصر قیام اپارٹمنٹس |

  ps/fa/ur wording to be checked by the owner before release (ps uses ټ / ډ as written).
- **`categories.kind`** (string, default `"item"`; `"stay"` on the Stays root). A child inherits
  its root's kind (`Category#effective_kind`). Clients never hard-code slugs: the API sends
  `kind` on every category, and a client switches form, detail and filters on `kind == "stay"`.
  The next type (Jobs: "salary per month") is a new kind, not new client code paths.
- **The existing `Property › Guest Houses` (slug `guest-houses`) MOVES under Stays** (same row,
  same id), so its listings follow. The move is its own reversible data migration
  (`20261016100200_move_guest_houses_to_stays`, `StaysTree.move_guest_houses!` /
  `restore_guest_houses!`), separate from the tree (`20261016100100`). **Option B** = delete that one
  migration (and its seeds line) and add a `guest-stays` row to `StaysTree::CHILDREN`. They have no `price_unit` (shown as a plain price, as today)
  and no details. **Open question for the owner:** were those listings sold or let, rather than
  stayed in? If so, they stay under Property and Stays gets its own `guest-stays` slug.

### 2.2 Price unit: a listing column, not the category's
- **`listings.price_unit`**: string, nullable, one of `night`, `month`. `nil` means a total price
  (every item today).
- Stays: `night` by default, `month` allowed (a long stay). Property › Apartments for Rent and
  Shops & Offices may use `month` too (owner's "maybe"; cheap once the column exists). Everything
  else: `nil` only (validated).
- Clients show `AFN 1,500 / night` (`/ شپه`, `/ شب`, `/ رات`) and `AFN 20,000 / month`.
  Price filters are unit-aware only within one category (a stays search compares nights to nights).

### 2.3 Room details: one small typed `details` jsonb, validated per kind
- **`listings.details`**: jsonb, default `{}`, GIN-indexed. For `kind == "stay"`
  (`Listing::StayDetails`):

| key | type | rule |
|---|---|---|
| `guests` | integer | 1–50, the maximum guests per room |
| `beds` | integer | 0–50 |
| `bathroom` | string | `private` or `shared` |
| `amenities` | array of strings | subset of `wifi, heating, ac, hot_water, parking, breakfast, kitchen, tv, power_backup, family_only` |
| `check_in`, `check_out` | string | `HH:MM` |

  - `power_backup` (generator/solar) and `family_only` ("families only") are local needs.
  - Every key is **optional**, so the shipped 1.1.6 app, which sends no details, can still post a stay.
  - Unknown keys are refused (422). For non-stay listings, `details` must be empty.
- Not a set of columns: rooms are the first of several kinds, and one validated hash keeps
  `listings` narrow.

### 2.4 Lifecycle: the same four statuses, a stay's own words
- Statuses are unchanged (draft / active ⇄ reserved / sold). See CLAUDE.md "Listing Lifecycle":
  no reserve-before-sell, a hold is a badge, never a dead end.
- **Condition** is hidden for stays (form and detail), and the API ignores it there.
- **Mark sold makes no sense for a room** that is let again tomorrow. For stays, the seller's
  primary action is **"Pause / Show again"** (the existing unpublish / publish). The chat hold
  ("Held for {name}") stays: it is how a host says *this room is kept for you*. "Mark sold" is
  not offered for stays in 1.1.7 clients. The API still accepts it, so nothing breaks.
- `quantity` = **identical rooms** ("3 double rooms"), with the multi-unit rules as they are.

### 2.5 A hotel is a SHOP
- A hotel / guest house uses the existing **shop** (profile, logo, hours, verification, team).
  Its rooms are listings in that shop. A shop whose category is Stays shows **"Rooms"** instead
  of "Products" (copy only). No new model.

### 2.6 Search
- The existing filters apply as they are: `category_id=<stays>` (children included), city /
  `location`, radius + `sort=nearest` (the map pin), `price_min/max`, `sort=price_asc`.
- **New query params** (index + SQL):
  - `guests=N` → `(details->>'guests')::int >= N`;
  - `amenities[]=wifi&amenities[]=breakfast` → `details->'amenities' @> '[…]'`;
  - `price_unit=night`.
  Ignored for non-stay categories. Unreadable values are ignored, the same rule as today.
- Mobile + web: when the chosen category is a stay, the filter sheet adds **Guests** (stepper)
  and **Amenities** (chips). "Price" reads "Price per night".

### 2.7 Web SEO (honest JSON-LD only)
- A stay listing page: `@type: "Accommodation"` (`HotelRoom` for `hotel-rooms`), `occupancy`
  from `guests`, `amenityFeature` from amenities, and an `Offer` whose `priceSpecification` is a
  `UnitPriceSpecification` with `unitText: "night"`. No ratings unless real reviews exist, and no
  `availability` claims.
- A stays shop page: `LodgingBusiness` (name, address, geo, telephone if public).
- Category landing pages `/stays`, `/stays/hotel-rooms` keep the existing SSR + sitemap.

### 2.8 Where it changes

| Layer | Change |
|---|---|
| API | migration: `categories.kind`, `listings.price_unit`, `listings.details` (+ GIN); data migration: the Stays tree (idempotent upsert, moves `guest-houses`); `Listing` validations + `StayDetails`; serializer adds `price_unit`, `details`, `category.kind`; index filters `guests`, `amenities[]`, `price_unit`; seeds + QA samples; RSpec + RSwag |
| Admin | category form: `kind`; listing show: details |
| Mobile 1.1.7 | ListingForm: stay fields when kind is stay (steppers, bathroom, amenities chips, check-in/out, price unit), condition hidden; listing detail: facts line + amenities + check-in/out; PriceTag/ListingCard: `/ night`; FilterSheet: guests + amenities; seller actions Pause/Show again for stays; en/ps/fa/ur; Jest + Maestro flow |
| Web 1.1.7 | the same on listing-form, listing page, cards, bazaar filters; JSON-LD; Playwright: mock e2e + e2e-real "a stay" |
| MCP / AI | nothing in 1.1.7 |

### 2.9 Backward compatibility (the shipped 1.1.6 app and web)
- They ignore unknown keys: `price_unit`, `details` and `category.kind` are invisible to them. A
  stay shows as a normal listing with its price (no "/ night") and its description. That is
  acceptable, and nothing crashes.
- A new top-level category and a moved subcategory are just tree data. Both 1.1.6 clients
  render the tree from `GET /categories`.
- A 1.1.6 seller can still post in Stays: `price_unit` defaults to `night` server-side, and
  details are optional.
- The API ships first, and stays backward compatible on its own.

## 3. Not in scope
Online booking, availability calendar, nightly pricing rules, payments, deposits, star ratings,
check-in flows, per-guest pricing.
