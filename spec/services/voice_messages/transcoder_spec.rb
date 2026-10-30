require "rails_helper"

RSpec.describe VoiceMessages::Transcoder, :ffmpeg do
  def call(path) = described_class.call(path)

  def refused_with(path)
    call(path)
    nil
  rescue described_class::Refused => e
    e.code
  end

  describe "the stored clip" do
    it "turns an iPhone/Android m4a into one AAC .m4a, measured" do
      clip = call(voice_clip(seconds: 3, format: :m4a))

      expect(Marcel::MimeType.for(StringIO.new(clip.data))).to eq("audio/mp4")
      expect(clip.duration_ms).to be_within(150).of(3000)
      expect(clip.waveform.size).to eq(64)
      expect(clip.waveform).to all(be_between(0, 100))
      expect(clip.waveform.max).to eq(100)
    end

    it "turns a web recording (WebM/Opus, which the iOS app cannot play) into the same m4a" do
      clip = call(voice_clip(seconds: 2, format: :webm))

      expect(Marcel::MimeType.for(StringIO.new(clip.data))).to eq("audio/mp4")
      expect(clip.duration_ms).to be_within(150).of(2000)
    end

    it "reads an Ogg/Opus recording too" do
      expect(call(voice_clip(seconds: 2, format: :ogg)).duration_ms).to be_within(150).of(2000)
    end

    it "keeps nothing but the sound: the recorder's tags are gone" do
      clip = call(voice_clip(metadata: { title: "SECRET-TITLE-TAG", location: "+34.5553+069.2075/" }))

      expect(clip.data).not_to include("SECRET-TITLE-TAG")
      expect(clip.data).not_to include("+34.5553")
    end

    it "is small: 2 minutes stay well under the 2 MB cap" do
      clip = call(voice_clip(seconds: 120))

      expect(clip.data.bytesize).to be < 800.kilobytes
      expect(clip.duration_ms).to be_within(200).of(120_000)
    end
  end

  describe "refusals" do
    it "a clip under 1 second: voice_too_short" do
      expect(refused_with(voice_clip(seconds: 0.5))).to eq(:voice_too_short)
    end

    it "a clip over 2 minutes: voice_too_long" do
      expect(refused_with(voice_clip(seconds: 130, format: :ogg))).to eq(:voice_too_long)
    end

    it "a file over 2 MB: voice_too_large, before ffmpeg ever runs" do
      path = voice_file_with("\x00\x00\x00\x18ftypM4A ".b + ("\x00".b * (2.megabytes + 1)))
      expect(Open3).not_to receive(:capture3)

      expect(refused_with(path)).to eq(:voice_too_large)
    end

    it "a missing file: voice_missing" do
      expect(refused_with("/nonexistent/voice.m4a")).to eq(:voice_missing)
    end
  end

  # Security (docs/VOICE_MESSAGES.md §8.1): the upload is untrusted input to ffmpeg.
  describe "hardening" do
    it "an HLS playlist renamed .m4a is refused unread: ffmpeg never starts" do
      playlist = voice_file_with("#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:10,\nfile:///etc/passwd\n#EXT-X-ENDLIST\n")
      expect(Open3).not_to receive(:capture3)

      expect(refused_with(playlist)).to eq(:voice_invalid)
    end

    it "an ffconcat list renamed .m4a is refused unread: ffmpeg never starts" do
      list = voice_file_with("ffconcat version 1.0\nfile '/etc/passwd'\n")
      expect(Open3).not_to receive(:capture3)

      expect(refused_with(list)).to eq(:voice_invalid)
    end

    it "random bytes are refused unread" do
      expect(Open3).not_to receive(:capture3)

      expect(refused_with(voice_file_with(SecureRandom.random_bytes(4096)))).to eq(:voice_invalid)
    end

    it "an MP4 header over garbage reaches ffmpeg, which fails: voice_invalid" do
      fake = voice_file_with("\x00\x00\x00\x18ftypM4A \x00\x00\x02\x00M4A isom".b + SecureRandom.random_bytes(2048))

      expect(refused_with(fake)).to eq(:voice_invalid)
    end

    it "a video with no sound is not a voice message" do
      path = Rails.root.join("tmp/voice_spec_#{SecureRandom.hex(4)}.mp4").to_s
      system("ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=red:s=64x64:d=2", "-an", path)
      voice_files << path

      expect(refused_with(path)).to eq(:voice_invalid)
    end

    it "runs ffmpeg with the container named, files only, no stdin, under a hard kill" do
      argv = nil
      allow(Open3).to receive(:capture3).and_wrap_original { |m, *args| argv = args; m.call(*args) }

      call(voice_clip(format: :webm))

      expect(argv.first(4)).to eq([ "timeout", "-s", "KILL", "10" ])
      expect(argv).to include("-nostdin")
      expect(argv.each_cons(2).to_a).to include([ "-protocol_whitelist", "file" ], [ "-f", "matroska" ])
      expect(argv.index("-f")).to be < argv.index("-i")
    end

    it "removes its temp dir, refused or not" do
      before = Dir.glob(File.join(Dir.tmpdir, "voice*"))
      call(voice_clip)
      refused_with(voice_file_with("\x00\x00\x00\x18ftypM4A ".b + SecureRandom.random_bytes(512)))

      expect(Dir.glob(File.join(Dir.tmpdir, "voice*")) - before).to be_empty
    end
  end

  describe ".container_of" do
    it "knows the three containers by their leading bytes" do
      expect(described_class.container_of(voice_clip(format: :m4a))).to eq(:mp4)
      expect(described_class.container_of(voice_clip(format: :webm))).to eq(:webm)
      expect(described_class.container_of(voice_clip(format: :ogg))).to eq(:ogg)
      expect(described_class.container_of(voice_file_with("#EXTM3U\n"))).to be_nil
    end
  end
end
