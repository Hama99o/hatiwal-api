class BackfillListingCoordinatesFromProvince < ActiveRecord::Migration[8.1]
  # Province (capital) coordinates — mirrors the mobile app's afghan_provinces
  # data so listings created with a province text but no coordinates become
  # findable on the buyer's map / distance search.
  PROVINCE_COORDS = {
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
    "Kapisa" => [ 34.9810, 69.3220 ], "Panjshir" => [ 35.3105, 69.5400 ]
  }.freeze

  def up
    PROVINCE_COORDS.each do |province, (lat, lng)|
      execute(<<~SQL.squish)
        UPDATE listings
        SET latitude = #{lat}, longitude = #{lng}
        WHERE location = #{ActiveRecord::Base.connection.quote(province)}
          AND (latitude IS NULL OR longitude IS NULL)
      SQL
    end
  end

  def down
    # No-op: we don't know which coordinates were backfilled vs. user-set.
  end
end
