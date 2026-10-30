require "swagger_helper"

# Voice messages in chat (1.2.1, docs/VOICE_MESSAGES.md).
RSpec.describe "Api::V1::Messages — voice messages", type: :request do
  let(:buyer)        { create(:user) }
  let(:seller)       { create(:user) }
  let(:listing)      { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }
  let(:headers)      { auth_headers_for(buyer) }

  # Signs in once per user (each sign-in counts against the sign-in limit).
  def send_voice(file, conv: conversation, as: buyer, extra: {})
    @signed_in ||= {}
    post "/api/v1/conversations/#{conv.id}/messages",
         params: { kind: "voice_message", attachment: file }.merge(extra),
         headers: (@signed_in[as.id] ||= auth_headers_for(as))
  end

  # A clip the transcoder "made", for specs about everything around it.
  def stub_clip(duration_ms: 12_000)
    clip = VoiceMessages::Transcoder::Clip.new(data: "\x00\x00\x00\x18ftypM4A ".b + ("\x00".b * 64),
                                               duration_ms: duration_ms, waveform: Array.new(64, 50))
    allow(VoiceMessages::Transcoder).to receive(:available?).and_return(true)
    allow(VoiceMessages::Transcoder).to receive(:call).and_return(clip)
  end

  path "/api/v1/conversations/{conversation_id}/messages" do
    parameter name: :conversation_id, in: :path, type: :integer, required: true

    post("send a voice message") do
      tags "Messages"
      description <<~DESC
        `kind: "voice_message"` with the recording as `attachment` (multipart).
        Any of MP4/M4A, WebM or Ogg, ≤ 2 MB, 1 s – 2 min. The server re-encodes it
        to AAC `.m4a` (the one format every client plays), measures it and sets
        `body` to "🎤 m:ss" (what apps ≤ 1.2.0 show). The answer carries
        `voice: { url, duration_ms, waveform }` (64 bars, 0–100).
        Refusals (422 `code`): voice_missing, voice_too_large, voice_too_short,
        voice_too_long, voice_invalid. 503 `voice_messages_unavailable` when the
        server cannot take voice messages (`GET /app_config` features.voice_messages).
        60 voice messages an hour per user, inside the chat's 120 messages an hour.
      DESC
      consumes "multipart/form-data"
      produces "application/json"
      parameter name: :kind, in: :formData, type: :string, enum: [ "voice_message" ], required: true
      parameter name: :attachment, in: :formData, type: :file, required: true
      parameter name: :client_uuid, in: :formData, type: :string, required: false
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      let(:conversation_id) { conversation.id }
      let(:kind) { "voice_message" }
      let(:"access-token") { headers["access-token"] }
      let(:client) { headers["client"] }
      let(:uid) { headers["uid"] }

      response(201, "sent, re-encoded and measured") do
        let(:attachment) { voice_upload(voice_clip(seconds: 3, format: :webm), type: "audio/webm") }

        before do |example|
          skip("ffmpeg is not installed here (the production image has it)") unless VoiceMessages::Transcoder.available?
          submit_request(example.metadata)
        end

        it "stores an m4a with its duration and waveform" do
          msg = response.parsed_body["message"]
          expect(response).to have_http_status(:created)
          expect(msg["kind"]).to eq("voice_message")
          expect(msg["body"]).to eq("🎤 0:03")
          expect(msg["voice"]["duration_ms"]).to be_within(150).of(3000)
          expect(msg["voice"]["waveform"].size).to eq(64)
          expect(msg["voice"]["url"]).to be_present
          expect(Message.last.attachment.blob.content_type).to eq("audio/mp4")
        end
      end

      response(422, "an HLS playlist renamed .m4a: voice_invalid, never processed") do
        let(:attachment) { voice_upload(voice_file_with("#EXTM3U\n#EXTINF:1,\nfile:///etc/passwd\n")) }

        before do
          allow(VoiceMessages::Transcoder).to receive(:available?).and_return(true)
          expect(Open3).not_to receive(:capture3)
        end

        run_test! do
          expect(response.parsed_body["code"]).to eq("voice_invalid")
          expect(Message.count).to eq(0)
        end
      end
    end
  end

  describe "sending", :ffmpeg do
    it "takes the phone's m4a" do
      send_voice(voice_upload(voice_clip(seconds: 2)))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("message", "body")).to eq("🎤 0:02")
    end

    it "refuses a clip under 1 second: voice_too_short" do
      send_voice(voice_upload(voice_clip(seconds: 0.4)))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("voice_too_short")
    end

    it "refuses an ffconcat list renamed .m4a, unread" do
      expect(Open3).not_to receive(:capture3)
      send_voice(voice_upload(voice_file_with("ffconcat version 1.0\nfile '/etc/passwd'\n")))

      expect(response.parsed_body["code"]).to eq("voice_invalid")
    end

    it "is refused in the Support thread (no player for the admins there)" do
      support = Conversation.support_thread_for!(buyer)
      send_voice(voice_upload(voice_clip), conv: support)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Message.where(kind: :voice_message)).to be_empty
    end
  end

  describe "around the transcoder" do
    it "with no file: voice_missing" do
      stub_clip
      send_voice(nil)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("voice_missing")
    end

    it "over 2 MB: voice_too_large" do
      allow(VoiceMessages::Transcoder).to receive(:available?).and_return(true)
      send_voice(voice_upload(voice_file_with("\x00\x00\x00\x18ftypM4A ".b + ("\x00".b * (2.megabytes + 1)))))

      expect(response.parsed_body["code"]).to eq("voice_too_large")
    end

    it "takes voice in a shop chat" do
      shop = create(:shop, owner: seller)
      chat = Conversations::StartShopService.new(buyer: buyer, shop: shop, message_body: "Salaam").call
      stub_clip
      send_voice(voice_upload(voice_file_with("x")), conv: chat)

      expect(response).to have_http_status(:created)
    end

    it "answers 503 voice_messages_unavailable with the kill switch" do
      stub_clip
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("VOICE_MESSAGES_ENABLED").and_return("0")
      send_voice(voice_upload(voice_file_with("x")))

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["code"]).to eq("voice_messages_unavailable")
    end

    it "the body is the server's, whatever the client sent" do
      stub_clip(duration_ms: 72_400)
      send_voice(voice_upload(voice_file_with("x")), extra: { body: "something else" })

      expect(response.parsed_body.dig("message", "body")).to eq("🎤 1:12")
    end

    it "a resend with the same client_uuid returns the stored one, never a second message" do
      stub_clip
      uuid = SecureRandom.uuid
      2.times { send_voice(voice_upload(voice_file_with("x")), extra: { client_uuid: uuid }) }

      expect(Message.where(kind: :voice_message).count).to eq(1)
    end

    it "notifies like any message (cable + push)" do
      stub_clip
      expect { send_voice(voice_upload(voice_file_with("x"))) }
        .to have_enqueued_job(SendMessagePushJob).and have_enqueued_job(BroadcastMessageJob)
    end

    it "60 voice messages an hour per user, then 429" do
      stub_clip
      60.times do |i|
        send_voice(voice_upload(voice_file_with("x")))
        expect(response).to have_http_status(:created), "voice #{i + 1} was refused"
      end
      send_voice(voice_upload(voice_file_with("x")))
      expect(response).to have_http_status(:too_many_requests)

      post "/api/v1/conversations/#{conversation.id}/messages", params: { body: "still fine" }, headers: headers
      expect(response).to have_http_status(:created)
    end

    it "an audio file on a non-voice kind is refused (only the server's own m4a is ever stored)" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { kind: "document", body: "a.m4a", attachment: voice_upload(voice_file_with("\x00\x00\x00\x18ftypM4A ".b + ("\x00".b * 64))) },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "reading" do
    let!(:voice) { create(:message, :voice, conversation: conversation, user: seller) }

    it "lists it with its voice block" do
      get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json

      msg = response.parsed_body["messages"].find { |m| m["id"] == voice.id }
      expect(msg["voice"]).to include("duration_ms" => 12_000, "waveform" => Array.new(64, 40))
      expect(msg["voice"]["url"]).to be_present
    end

    it "a text message has voice: null" do
      text = create(:message, conversation: conversation, user: seller)
      get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json

      expect(response.parsed_body["messages"].find { |m| m["id"] == text.id }["voice"]).to be_nil
    end

    it "deleting it purges the audio; the tombstone has nothing to play" do
      blob_id = voice.attachment.blob.id
      perform_enqueued_jobs do
        delete "/api/v1/conversations/#{conversation.id}/messages/#{voice.id}", headers: auth_headers_for(seller)
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("message", "voice")).to be_nil
      expect(ActiveStorage::Blob.exists?(blob_id)).to be false
    end
  end
end
