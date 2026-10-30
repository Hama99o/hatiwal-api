# The local clock of a place we only know by its province: Pakistan's provinces
# are on Asia/Karachi, the rest (Afghanistan, and anything we cannot place) on
# Asia/Kabul. Used by shops (opening hours) and users (alert quiet hours).
module LocalTimeZone
  PAKISTAN_PROVINCES = [ "Punjab", "Sindh", "Khyber Pakhtunkhwa", "Balochistan", "Islamabad", "Gilgit-Baltistan", "Azad Kashmir" ].freeze

  def self.for_province(province) = PAKISTAN_PROVINCES.include?(province) ? "Asia/Karachi" : "Asia/Kabul"

  def time_zone = LocalTimeZone.for_province(province)
end
