# Sell with a photo (docs/SELL_WITH_PHOTO.md): CLIP's TEXT half, the twin of
# ImageSearch::Embedder. It turns English phrases into vectors comparable with
# photo vectors (same model id and revision, so the same space).
#
# Only used to embed the category prompts (config/sell_photo/prompts.yml), a
# few dozen phrases, once per process and cache. The session is loaded for that
# one call and dropped after it, so the model (64 MB) holds no RAM in between.
#
# The files come from bin/fetch-image-model, at Docker build time.
module ImageSearch
  class TextEmbedder
    MODEL_FILE = "onnx/text_model_quantized.onnx".freeze
    VOCAB_FILE = "vocab.json".freeze
    MERGES_FILE = "merges.txt".freeze

    class << self
      def path(file) = File.join(Embedder.model_dir, Embedder::MODEL_ID, Embedder::MODEL_REVISION, file)

      def tokenizer_paths = [ path(VOCAB_FILE), path(MERGES_FILE) ]

      # True when the text model and its tokenizer files are all on disk.
      def available? = [ MODEL_FILE, VOCAB_FILE, MERGES_FILE ].all? { |file| File.file?(path(file)) }

      # phrases (Array of String) -> Array of unit-length vectors, same order.
      def embed_all(phrases)
        raise Embedder::Unavailable, "text model files missing in #{path('')}" unless available?

        tokenizer = ClipTokenizer.new(*tokenizer_paths)
        session = OnnxRuntime::InferenceSession.new(
          path(MODEL_FILE), intra_op_num_threads: Integer(ENV.fetch("IMAGE_SEARCH_THREADS", 2)), log_severity_level: 3
        )
        phrases.map do |phrase|
          output = session.run([ "text_embeds" ], { "input_ids" => [ tokenizer.encode(phrase) ] })
          Embedder.normalize(output.first.first)
        end
      end
    end
  end
end
