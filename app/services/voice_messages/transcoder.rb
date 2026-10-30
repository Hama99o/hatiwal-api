require "open3"

module VoiceMessages
  # Re-encodes an uploaded voice clip into the ONE format every client plays
  # (AAC-LC in .m4a, mono, 40 kbps, faststart) and measures it: its duration and
  # a 64-bar waveform come from the decoded sound, never from the client.
  #
  # Why re-encode everything: the web records WebM/Opus in Chrome on Linux and
  # Firefox, which the iOS app (AVPlayer) cannot play. Re-encoding also drops the
  # recorder's metadata (device, time, location tags): only the sound is stored.
  #
  # The upload is untrusted input to ffmpeg, so (security, docs/VOICE_MESSAGES.md §2):
  # - only three containers are accepted, recognized by their leading bytes
  #   BEFORE ffmpeg runs: MP4/M4A (`ftyp`), WebM/Matroska (EBML), Ogg (`OggS`).
  #   An HLS playlist, a concat list or anything else is refused unread;
  # - ffmpeg is told the container (`-f`), so it never probes for one (no hls,
  #   concat or image2 demuxer can be picked by a crafted file), and may open
  #   only plain files (`-protocol_whitelist file`): no network, no pipes;
  # - `-nostdin`, a hard 10 s kill (`timeout -s KILL`), a 125 s cap on what it
  #   decodes, and a private temp dir removed in `ensure`;
  # - one ffmpeg at a time per process (see SLOTS).
  class Transcoder
    MAX_BYTES = 2.megabytes
    MIN_DURATION_MS = 1_000
    # 2 minutes, plus slack for a recorder that stops a moment late.
    MAX_DURATION_MS = 122_000
    TIMEOUT_SECONDS = 10
    # Decode no more than this: a clip claiming hours never costs more.
    DECODE_CAP_SECONDS = 125
    WAVEFORM_BARS = 64
    PCM_RATE = 8_000

    # One ffmpeg at a time per process. Production Puma has few threads (3 by
    # default, Solid Queue inside it): three 2-minute clips at once would hold
    # every one of them for seconds. A second clip waits this long for the slot,
    # then is answered 503 voice_busy (+ Retry-After); the apps' outbox retries.
    SLOTS = 1
    WAIT_SECONDS = 5

    # leading bytes → the ffmpeg demuxer that reads them
    CONTAINERS = {
      mp4: "mov",
      webm: "matroska",
      ogg: "ogg"
    }.freeze

    Clip = Data.define(:data, :duration_ms, :waveform)

    # The slot stayed taken for WAIT_SECONDS: try again shortly (503 voice_busy).
    class Busy < StandardError; end

    # A clip we refuse; `code` is the wire code the apps translate.
    class Refused < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code.to_s)
      end
    end

    def self.available?
      return @available unless @available.nil?

      @available = system("ffmpeg", "-version", out: File::NULL, err: File::NULL) == true
    end

    def self.call(path)
      new(path).call
    end

    # Runs the block holding the process's transcode slot, or raises Busy.
    def self.with_slot
      token = slot_queue.pop(timeout: self::WAIT_SECONDS)
      raise Busy unless token

      begin
        yield
      ensure
        slot_queue.push(token)
      end
    end

    def self.slot_queue
      @slot_queue ||= Thread::Queue.new(Array.new(SLOTS, :slot))
    end
    private_class_method :slot_queue

    def self.container_of(path)
      head = File.binread(path, 12).to_s
      return :mp4 if head.byteslice(4, 4) == "ftyp"
      return :webm if head.start_with?("\x1A\x45\xDF\xA3".b)
      return :ogg if head.start_with?("OggS")

      nil
    end

    def initialize(path)
      @path = path.to_s
    end

    def call
      raise Refused, :voice_missing unless File.file?(@path)
      raise Refused, :voice_too_large if File.size(@path) > MAX_BYTES

      container = self.class.container_of(@path)
      raise Refused, :voice_invalid unless container

      Dir.mktmpdir("voice") do |dir|
        out = File.join(dir, "voice.m4a")
        pcm = File.join(dir, "voice.pcm")
        self.class.with_slot { run_ffmpeg(CONTAINERS.fetch(container), out, pcm) }
        clip_from(out, pcm)
      end
    end

    private

    def run_ffmpeg(demuxer, out, pcm)
      cmd = [
        "timeout", "-s", "KILL", TIMEOUT_SECONDS.to_s,
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-threads", "1",
        "-protocol_whitelist", "file",
        "-f", demuxer, "-i", @path,
        # 1. the stored clip
        "-map", "0:a:0", "-t", DECODE_CAP_SECONDS.to_s, "-map_metadata", "-1", "-vn", "-sn", "-dn",
        "-ac", "1", "-ar", "24000", "-c:a", "aac", "-b:a", "40k", "-movflags", "+faststart",
        "-f", "ipod", out,
        # 2. the sound as raw samples, to measure it
        "-map", "0:a:0", "-t", DECODE_CAP_SECONDS.to_s,
        "-ac", "1", "-ar", PCM_RATE.to_s, "-c:a", "pcm_s16le", "-f", "s16le", pcm
      ]
      _out, err, status = Open3.capture3(*cmd)
      return if status.success?

      Rails.logger.info("[voice] ffmpeg refused a clip (exit #{status.exitstatus}): #{err.to_s.lines.first(3).join.strip}")
      raise Refused, :voice_invalid
    end

    def clip_from(out, pcm)
      samples = File.binread(pcm).unpack("s<*")
      duration_ms = (samples.size * 1000.0 / PCM_RATE).round
      raise Refused, :voice_invalid if samples.empty? || !File.size?(out)
      raise Refused, :voice_too_short if duration_ms < MIN_DURATION_MS
      raise Refused, :voice_too_long if duration_ms > MAX_DURATION_MS

      Clip.new(data: File.binread(out), duration_ms: duration_ms, waveform: waveform_of(samples))
    end

    # The loudness (RMS) of 64 equal slices, scaled so the loudest is 100. A
    # silent clip is all zeros; the clients draw a minimum bar height.
    def waveform_of(samples)
      slice = (samples.size / WAVEFORM_BARS.to_f).ceil
      levels = samples.each_slice(slice).map { |part| Math.sqrt(part.sum { |s| s * s } / part.size.to_f) }
      levels.fill(0.0, levels.size...WAVEFORM_BARS)
      peak = levels.max
      return Array.new(WAVEFORM_BARS, 0) unless peak&.positive?

      levels.first(WAVEFORM_BARS).map { |l| (l * 100 / peak).round }
    end
  end
end
