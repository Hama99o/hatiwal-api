# The countries Hatiwal serves: Afghanistan, Pakistan and Iran. A location
# outside them is never used as a default or saved as a guess; Kabul is used
# instead (owner's rule, 2026-10-05; docs/USER_LOCATION.md in hatiwal-mobile).
#
# A PORT of hatiwal-mobile/src/lib/serviceArea.ts — the same hand-traced
# outline, point for point, and the same ~13 km margin so border towns
# (Herat, Torkham, Zahedan…) never fall out. Change both together, never one:
# the API and the apps must agree on what "inside" means.
module ServiceArea
  # [longitude, latitude], clockwise from Iran's north-west corner.
  OUTLINE = [
    [ 44.0, 39.4 ], [ 45.0, 39.7 ], [ 46.5, 38.9 ], [ 48.0, 38.4 ], [ 48.9, 38.4 ],
    [ 49.0, 37.6 ], [ 50.5, 37.0 ], [ 53.9, 36.9 ], [ 54.0, 37.4 ], [ 55.4, 38.1 ],
    [ 57.3, 38.2 ], [ 59.6, 37.1 ], [ 61.1, 36.6 ], [ 61.3, 35.6 ], [ 62.3, 35.3 ],
    [ 63.1, 35.9 ], [ 64.5, 36.3 ], [ 65.6, 37.4 ], [ 66.5, 37.4 ], [ 67.8, 37.2 ],
    [ 68.9, 37.3 ], [ 70.2, 37.6 ], [ 71.5, 37.9 ], [ 72.6, 37.0 ], [ 74.9, 37.4 ],
    [ 75.7, 36.7 ], [ 77.0, 35.6 ], [ 77.8, 35.5 ], [ 76.0, 34.6 ], [ 74.0, 34.4 ],
    [ 74.6, 33.0 ], [ 75.4, 32.3 ], [ 74.95, 31.95 ], [ 74.57, 31.6 ], [ 74.55, 31.1 ], [ 73.9, 30.0 ], [ 72.9, 29.0 ],
    [ 71.9, 27.9 ], [ 70.6, 27.7 ], [ 70.3, 26.5 ], [ 70.0, 25.7 ], [ 70.9, 24.3 ],
    [ 68.8, 23.8 ], [ 67.0, 24.8 ], [ 66.6, 25.4 ], [ 64.0, 25.2 ], [ 62.3, 25.0 ], [ 61.6, 25.0 ],
    [ 60.5, 25.3 ], [ 59.0, 25.4 ], [ 57.3, 25.8 ], [ 56.3, 27.0 ], [ 54.0, 26.5 ],
    [ 52.5, 27.4 ], [ 51.4, 27.9 ], [ 50.3, 29.2 ], [ 49.0, 30.0 ], [ 48.4, 30.0 ],
    [ 48.0, 30.5 ], [ 47.7, 31.0 ], [ 47.4, 32.4 ], [ 46.1, 33.0 ], [ 45.4, 33.9 ],
    [ 45.5, 34.8 ], [ 46.1, 35.2 ], [ 45.4, 35.9 ], [ 44.8, 37.2 ], [ 44.3, 38.4 ]
  ].freeze

  MARGIN_DEG = 0.12

  # Kabul — mobile's DEFAULT_CENTER (src/components/common/map/MapCanvas.types.ts).
  DEFAULT = { latitude: 34.5553, longitude: 69.2075, province: "Kabul" }.freeze

  # Province capitals, keyed by the stored `value` — a port of
  # hatiwal-mobile/src/data/afghan_provinces.ts (34 Afghan + 7 Pakistani).
  PROVINCE_CAPITALS = {
    "Kabul" => [ 34.5553, 69.2075 ], "Kandahar" => [ 31.6133, 65.7101 ],
    "Herat" => [ 34.3529, 62.2040 ], "Nangarhar" => [ 34.4265, 70.4515 ],
    "Balkh" => [ 36.7090, 67.1109 ], "Kunduz" => [ 36.7286, 68.8681 ],
    "Ghazni" => [ 33.5492, 68.4173 ], "Parwan" => [ 35.0136, 69.1683 ],
    "Logar" => [ 34.0015, 69.0466 ], "Khost" => [ 33.3395, 69.9205 ],
    "Paktia" => [ 33.5970, 69.2257 ], "Paktika" => [ 33.1761, 68.7178 ],
    "Laghman" => [ 34.6680, 70.2089 ], "Kunar" => [ 34.8742, 71.1462 ],
    "Nuristan" => [ 35.4264, 70.9181 ], "Badakhshan" => [ 37.1166, 70.5800 ],
    "Takhar" => [ 36.7361, 69.5345 ], "Baghlan" => [ 35.9482, 68.7150 ],
    "Samangan" => [ 36.2659, 68.0150 ], "Sar-e Pol" => [ 36.2159, 65.9333 ],
    "Jawzjan" => [ 36.6657, 65.7529 ], "Faryab" => [ 35.9211, 64.7842 ],
    "Badghis" => [ 34.9853, 63.1287 ], "Ghor" => [ 34.5267, 65.2680 ],
    "Daykundi" => [ 33.7220, 66.1300 ], "Bamyan" => [ 34.8210, 67.8270 ],
    "Wardak" => [ 34.3961, 68.8669 ], "Zabul" => [ 32.1058, 66.9070 ],
    "Uruzgan" => [ 32.6266, 65.8694 ], "Helmand" => [ 31.5938, 64.3715 ],
    "Nimroz" => [ 31.0125, 61.8628 ], "Farah" => [ 32.3742, 62.1135 ],
    "Kapisa" => [ 34.9810, 69.3220 ], "Panjshir" => [ 35.3105, 69.5400 ],
    "Punjab" => [ 31.5204, 74.3587 ], "Sindh" => [ 24.8607, 67.0011 ],
    "Khyber Pakhtunkhwa" => [ 34.0151, 71.5249 ], "Balochistan" => [ 30.1798, 66.9750 ],
    "Islamabad" => [ 33.6844, 73.0479 ], "Gilgit-Baltistan" => [ 35.9208, 74.3082 ],
    "Azad Kashmir" => [ 34.3700, 73.4711 ]
  }.freeze

  # A point further than this from every capital gets no province name: an
  # Iranian city must not be labelled with the nearest Afghan province.
  PROVINCE_RADIUS_DEG = 1.5

  module_function

  # True when the point is in Afghanistan, Pakistan or Iran (or within ~13 km of their border).
  def include?(latitude, longitude)
    lat = Float(latitude, exception: false)
    lng = Float(longitude, exception: false)
    return false unless lat&.finite? && lng&.finite?

    inside_outline?(lng, lat) || distance_to_outline(lng, lat) <= MARGIN_DEG
  end

  # The capital of a stored province value, or nil when it is not one we know.
  def province_center(value)
    PROVINCE_CAPITALS[value.to_s.strip]
  end

  # The province named in free text such as a listing's "Herat, City Center".
  def province_in_text(text)
    first = text.to_s.split(",").first.to_s.strip.downcase
    PROVINCE_CAPITALS.keys.find { |name| name.downcase == first }
  end

  # The province whose capital is closest to the point, when one is close enough.
  def nearest_province(latitude, longitude)
    lat = latitude.to_f
    lng = longitude.to_f
    name, (plat, plng) = PROVINCE_CAPITALS.min_by { |_n, (a, b)| Math.hypot(a - lat, b - lng) }
    Math.hypot(plat - lat, plng - lng) <= PROVINCE_RADIUS_DEG ? name : nil
  end

  def inside_outline?(lng, lat)
    inside = false
    j = OUTLINE.length - 1
    OUTLINE.each_with_index do |(xi, yi), i|
      xj, yj = OUTLINE[j]
      inside = !inside if (yi > lat) != (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi
      j = i
    end
    inside
  end

  def distance_to_outline(lng, lat)
    j = OUTLINE.length - 1
    OUTLINE.each_with_index.map do |(bx, by), i|
      ax, ay = OUTLINE[j]
      j = i
      dx = bx - ax
      dy = by - ay
      t = (((lng - ax) * dx + (lat - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0)
      Math.hypot(lng - (ax + t * dx), lat - (ay + t * dy))
    end.min
  end
end
