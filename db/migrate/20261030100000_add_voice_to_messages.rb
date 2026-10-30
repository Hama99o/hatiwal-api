# Voice messages (1.2.1, docs/VOICE_MESSAGES.md): the server measures the clip
# when it re-encodes it, so both values are facts, never the client's claim.
# Additive and nullable: every existing message keeps NULL.
class AddVoiceToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :voice_duration_ms, :integer
    # 64 bars, 0..100: every client draws the same waveform without the file.
    add_column :messages, :voice_waveform, :integer, array: true
  end
end
