# Voice messages (docs/VOICE_MESSAGES.md) need ffmpeg. Specs tagged `:ffmpeg`
# run the real ffmpeg and are skipped (with a reason) on a machine without it;
# the production image installs it (Dockerfile).
#
# Clips are made on the fly from ffmpeg's own tone generator, so no audio
# fixture is committed and any length can be asked for.
module VoiceMessageHelpers
  # A real clip of `seconds` in the given container, written to a temp file.
  # `metadata:` adds tags (title, location…) the server must strip.
  def voice_clip(seconds: 3, format: :m4a, metadata: {})
    codec = { m4a: %w[-c:a aac -f ipod], webm: %w[-c:a libopus -f webm], ogg: %w[-c:a libopus -f ogg] }.fetch(format)
    path = Rails.root.join("tmp/voice_spec_#{SecureRandom.hex(4)}.#{format}").to_s
    tags = metadata.flat_map { |k, v| [ "-metadata", "#{k}=#{v}" ] }
    ok = system("ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-f", "lavfi",
                "-i", "sine=frequency=440:duration=#{seconds}", "-ac", "1", *tags, *codec, path)
    raise "ffmpeg could not make a #{format} clip" unless ok

    voice_files << path
    path
  end

  # Any bytes, saved under a name of our choosing (e.g. a playlist called .m4a).
  def voice_file_with(bytes, name: "voice.m4a")
    path = Rails.root.join("tmp/voice_spec_#{SecureRandom.hex(4)}_#{name}").to_s
    File.binwrite(path, bytes)
    voice_files << path
    path
  end

  def voice_upload(path, type: "audio/mp4")
    Rack::Test::UploadedFile.new(path, type, true)
  end

  def voice_files
    @voice_files ||= []
  end
end

RSpec.configure do |config|
  config.include VoiceMessageHelpers

  config.before(:each, :ffmpeg) do
    skip("ffmpeg is not installed here (the production image has it)") unless VoiceMessages::Transcoder.available?
  end

  config.after { voice_files.each { |p| FileUtils.rm_f(p) } if defined?(@voice_files) }
end
