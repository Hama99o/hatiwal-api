# Seed photos

Real photos for the development / demo seed (`db/seeds.rb` via `SeedPhotos`), so a
fresh seed never depends on the network (loremflickr started answering 401 "Bot
check", and the seed silently left 75 of 116 listings photo-less).

- **License:** every file is **CC0 / public domain** (found through Openverse, hosted on
  Wikimedia Commons). No attribution is required; the source is recorded anyway.
- **Checked by eye** (2026-10-09): no faces, no problem text or branding (a car's own
  maker badge is the product itself); re-encoded to ≤ 1280 px, EXIF stripped, ≤ 230 KB.
- **Layout:** `<category slug>/<words>-<n>.jpg`. A listing gets photos from its top-level
  category, preferring files whose words match its title ("corolla", "sofa"…).
- **Adding one:** CC0/PD only, same checks, a row below. `spec/seeds/seed_photos_spec.rb`
  fails on a file without a row (or a row without a file), an empty or non-JPEG file,
  or one larger than 1600 px.

| File | Size | License | Source | Creator |
|---|---|---|---|---|
| `vehicles/car-corolla-1.jpg` | 1280×772 | CC0 | https://commons.wikimedia.org/w/index.php?curid=84858817 | Tokumeigakarinoaoshima |
| `vehicles/car-corolla-2.jpg` | 1280×958 | CC0 | https://commons.wikimedia.org/w/index.php?curid=28194483 | Tokumeigakarinoaoshima |
| `vehicles/car-interior-1.jpg` | 1280×683 | CC0 | https://commons.wikimedia.org/w/index.php?curid=70287655 | TTTNIS |
| `vehicles/car-wagon-1.jpg` | 1280×603 | CC0 | https://commons.wikimedia.org/w/index.php?curid=153555022 | TTTNIS |
| `vehicles/suv-1.jpg` | 1280×638 | CC0 | https://commons.wikimedia.org/w/index.php?curid=154330144 | TTTNIS |
| `vehicles/suv-2.jpg` | 1280×621 | CC0 | https://commons.wikimedia.org/w/index.php?curid=154330145 | TTTNIS |
| `vehicles/car-sedan-1.jpg` | 1280×634 | CC0 | https://commons.wikimedia.org/w/index.php?curid=150090592 | 先従隗始 |
| `vehicles/car-sedan-2.jpg` | 1280×719 | CC0 | https://commons.wikimedia.org/w/index.php?curid=150090240 | 先従隗始 |
| `vehicles/car-sedan-3.jpg` | 1280×853 | CC0 | https://commons.wikimedia.org/w/index.php?curid=149257875 | 先従隗始 |
| `vehicles/motorcycle-1.jpg` | 1280×960 | CC0 | https://commons.wikimedia.org/w/index.php?curid=186336890 | John Robert McPherson |
| `vehicles/motorcycle-scooter-1.jpg` | 1280×960 | CC0 | https://commons.wikimedia.org/w/index.php?curid=170723910 | Saimmx |
| `clothes/jacket-1.jpg` | 1089×1280 | CC0 | https://commons.wikimedia.org/w/index.php?curid=80506678 | kreativgarasch |
| `clothes/shoes-1.jpg` | 1280×617 | CC0 | https://commons.wikimedia.org/w/index.php?curid=30490966 | Daderot |
| `clothes/shoes-2.jpg` | 1280×794 | CC0 | https://commons.wikimedia.org/w/index.php?curid=30490836 | Daderot |
| `clothes/shoes-sneakers-1.jpg` | 1280×853 | CC0 | https://commons.wikimedia.org/w/index.php?curid=30490835 | Daderot |
| `clothes/shoes-kids-1.jpg` | 1280×959 | CC0 | https://commons.wikimedia.org/w/index.php?curid=176770447 | ELTORO.VET |
| `electronics/camera-1.jpg` | 1280×784 | CC0 | https://commons.wikimedia.org/w/index.php?curid=148296652 | Packer1028 |
| `electronics/phone-1.jpg` | 1280×811 | CC0 | https://commons.wikimedia.org/w/index.php?curid=129470457 | Skitterphoto |
| `electronics/laptop-1.jpg` | 1280×853 | CC0 | https://commons.wikimedia.org/w/index.php?curid=91470467 | Corinne Kutz |
| `home/chair-1.jpg` | 1241×1280 | CC0 | https://commons.wikimedia.org/w/index.php?curid=61155820 | Georges Jacob |
| `home/chair-2.jpg` | 1012×1280 | CC0 | https://commons.wikimedia.org/w/index.php?curid=61155673 | Louis Delanois |
| `home/sofa-1.jpg` | 1280×1024 | CC0 | https://commons.wikimedia.org/w/index.php?curid=60185047 | Jacques Jean-Baptiste Tilliard / Jean-Baptiste Tilliard |
| `home/sofa-2.jpg` | 1280×857 | CC0 | https://commons.wikimedia.org/w/index.php?curid=60185036 | Claude Sené |
| `home/sofa-3.jpg` | 1280×960 | CC0 | https://commons.wikimedia.org/w/index.php?curid=147265927 |  |
| `home/wardrobe-1.jpg` | 1280×960 | CC0 | https://commons.wikimedia.org/w/index.php?curid=169492852 | Profpcde |
