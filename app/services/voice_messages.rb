# Voice messages in chat (1.2.1, docs/VOICE_MESSAGES.md).
module VoiceMessages
  # On when ffmpeg is on this server, unless VOICE_MESSAGES_ENABLED=0 (the kill
  # switch). The apps read it from GET /app_config and hide the 🎤 when it is
  # off, so an API without ffmpeg never offers the feature.
  def self.enabled?
    return false if ENV["VOICE_MESSAGES_ENABLED"] == "0"

    Transcoder.available?
  end

  # The body every voice message carries: "🎤 0:12". It is what a 1.2.0-or-older
  # app shows (an unknown kind renders as a text bubble with its body) and the
  # inbox preview fallback, so it must read the same in every language.
  def self.body_for(duration_ms)
    seconds = (duration_ms / 1000.0).round
    format("🎤 %<m>d:%<s>02d", m: seconds / 60, s: seconds % 60)
  end
end
