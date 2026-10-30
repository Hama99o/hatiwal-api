# Search by image (docs/IMAGE_SEARCH.md): turns a photo into a 512-number
# CLIP vector, on this server's CPU.
#
# The model is CLIP ViT-B/32's image half, quantized (q8, 89 MB), run with
# onnxruntime. The feasibility test used the `informers` gem around the same
# ONNX file; this does the same steps without it: informers' preprocessing ran
# in pure Ruby (0.16 s of a 0.5 s photo), libvips does it in 0.05 s, and the
# vectors are identical (cosine 1.0000 on the seed photos, 2026-10-29).
#
# The model is loaded lazily, ONCE per process, the first time a photo is
# embedded (~0.3 GB of RAM, see docs/IMAGE_SEARCH.md §RAM), so only the
# processes that embed pay for it: the job worker for listing photos, the web
# process for a search. One photo at a time per process (LOCK): it caps the
# CPU one process can take, and a session run holds Ruby's GVL anyway.
#
# The model files are never downloaded at runtime: bin/fetch-image-model puts
# them in model_dir, at Docker build time in production.
module ImageSearch
  class Embedder
    # A photo the decoder could not read (not an image, truncated, a bomb).
    class InvalidImage < StandardError; end
    # A photo with (almost) nothing in it: a covered lens, a blank frame. CLIP
    # still gives it a vector, and it scores 0.73 against products shot on a
    # white background (docs/IMAGE_SEARCH.md §Tuning), so it is refused here.
    class PlainImage < InvalidImage; end
    # The model files are missing: search by image is off on this server.
    class Unavailable < StandardError; end

    MODEL_ID       = "Xenova/clip-vit-base-patch32".freeze
    # The Hugging Face commit the files come from. Pinned: a new revision could
    # change the vectors, and vectors from two models must never be compared.
    MODEL_REVISION = "6b7c523703ae26e39be4b03774966f8571c7f523".freeze
    MODEL_FILE     = "onnx/vision_model_quantized.onnx".freeze
    # Stored with every embedding. Change it whenever the model, its revision,
    # the file OR the preprocessing below changes, then run the backfill: rows
    # of another version are ignored by the search.
    MODEL_VERSION  = "clip-vit-b32-q8@6b7c523".freeze
    DIMENSIONS     = 512
    # CLIP's input: the shortest side resized to 224, a centre crop to 224x224,
    # then each channel normalised with CLIP's mean and std
    # (preprocessor_config.json of MODEL_REVISION).
    INPUT_SIZE = 224
    MEAN       = [ 0.48145466, 0.4578275, 0.40821073 ].freeze
    STD        = [ 0.26862954, 0.26130258, 0.27577711 ].freeze
    # Below this standard deviation (0-255 pixel values, all channels) a photo
    # is PlainImage. A blank frame is ~0, real product photos 30-80.
    PLAIN_MAX_DEVIATION = 6.0

    LOCK = Mutex.new

    class << self
      def model_dir
        ENV.fetch("IMAGE_SEARCH_MODEL_DIR", Rails.root.join("vendor/image_models").to_s)
      end

      def model_path = File.join(model_dir, MODEL_ID, MODEL_REVISION, MODEL_FILE)

      # True when the model file is on disk, so a photo can be embedded.
      def available? = File.file?(model_path)

      def loaded? = !@session.nil?

      # bytes (a String) -> unit-length Array of DIMENSIONS floats.
      def embed(bytes)
        pixels = pixel_values(bytes)
        output = LOCK.synchronize { session.run([ "image_embeds" ], { "pixel_values" => [ pixels ] }) }
        normalize(output.first.first)
      end

      # The photo as CLIP's input tensor: 3 planes (R, G, B) of 224 rows of 224
      # normalised floats. libvips decodes a 4000 px JPEG at reduced size
      # (shrink-on-load), honours EXIF rotation, and reads every type the
      # listing photos accept (jpeg, png, webp, gif, heic, avif).
      def pixel_values(bytes)
        raise InvalidImage, "empty file" if bytes.blank?

        # fail_on=truncated: a cut-off upload is refused, not searched as a
        # half-grey picture.
        image = Vips::Image.thumbnail_buffer(bytes, INPUT_SIZE, height: INPUT_SIZE, crop: :centre,
                                             option_string: "fail_on=truncated")
        image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?
        image = image.colourspace(:srgb) unless image.interpretation == :srgb
        image = image.extract_band(0, n: 3) if image.bands > 3
        raise PlainImage, "plain image" if image.deviate < PLAIN_MAX_DEVIATION

        image = ((image.cast(:float) / 255.0) - MEAN) / STD
        image.bandsplit.map { |plane| plane.write_to_memory.unpack("f*").each_slice(INPUT_SIZE).to_a }
      rescue Vips::Error => e
        raise InvalidImage, e.message.lines.first.to_s.strip
      end

      # A vector scaled to length 1, so a dot product IS the cosine similarity.
      def normalize(vector)
        norm = Math.sqrt(vector.sum { |x| x * x })
        raise InvalidImage, "empty embedding" unless norm.positive?

        vector.map { |x| x / norm }
      end

      private

      def session
        @session ||= load_session
      end

      def load_session
        raise Unavailable, "image model file missing: #{model_path}" unless available?

        OnnxRuntime::InferenceSession.new(
          model_path,
          intra_op_num_threads: Integer(ENV.fetch("IMAGE_SEARCH_THREADS", 2)),
          log_severity_level: 3
        )
      end
    end
  end
end
