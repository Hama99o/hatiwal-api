require "swagger_helper"

# A chat message's file (a voice clip, a photo, a document) must still open after the 5 minutes an Active Storage
# signed URL lives (1.2.1, device run 2026-10-30: a voice clip tapped 7 minutes after its thread loaded got a 404 —
# the app downloads on the first ▶︎ only, and the offline cache keeps a thread's JSON for hours).
#
#   GET /api/v1/conversations/:conversation_id/messages/:id/attachment
#     a participant → 302 to a FRESH short-lived signed URL; anyone else → 404 (no existence leak); 401 signed out.
#
# The JSON carries that stable route: `voice.url` (voice is new in 1.2.1, no app reads the old shape) and
# `attachment_stable_url` (new apps). `attachment_url` stays a signed URL for 1.2.0 apps, which load it without
# auth headers — but now valid for an hour instead of 5 minutes.
RSpec.describe "Message attachments", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:buyer)        { create(:user) }
  let(:seller)       { create(:user) }
  let(:listing)      { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }
  let!(:voice)       { create(:message, :voice, conversation: conversation, user: seller) }
  let!(:photo) do
    create(:message, conversation: conversation, user: seller, kind: :image_message, body: "photo.jpg").tap do |m|
      m.attachment.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "photo.jpg",
                          content_type: "image/jpeg")
    end
  end

  def thread_json(as: buyer)
    get "/api/v1/conversations/#{conversation.id}/messages", headers: auth_headers_for(as)
    response.parsed_body["messages"].index_by { |m| m["id"] }
  end

  # The bytes behind a URL from the JSON, following the stable route's redirect like a client does.
  def fetch(url, as: buyer)
    path = URI(url).request_uri
    get path, headers: path.start_with?("/api/") ? auth_headers_for(as) : {}
    return response unless response.redirect?

    get URI(response.location).request_uri
    response
  end

  describe "a voice clip" do
    it "plays when tapped long after the thread loaded (the URL in the JSON does not expire)" do
      url = thread_json.dig(voice.id, "voice", "url")

      travel 7.minutes do
        expect(fetch(url)).to have_http_status(:ok)
        expect(response.body.b).to eq(voice.attachment.download.b)
      end

      travel 3.days do
        expect(fetch(url)).to have_http_status(:ok)
      end
    end

    it "is the stable route, never a signed storage URL" do
      url = thread_json.dig(voice.id, "voice", "url")

      expect(url).to end_with("/api/v1/conversations/#{conversation.id}/messages/#{voice.id}/attachment")
      expect(url).not_to include("active_storage")
    end
  end

  describe "a photo" do
    it "attachment_url (1.2.0 apps, no auth headers) still loads 30 minutes later" do
      url = thread_json.dig(photo.id, "attachment_url")

      travel 30.minutes do
        expect(fetch(url)).to have_http_status(:ok)
      end
    end

    it "attachment_stable_url loads days later" do
      url = thread_json.dig(photo.id, "attachment_stable_url")

      travel 3.days do
        expect(fetch(url)).to have_http_status(:ok)
        expect(response.media_type).to eq("image/jpeg")
      end
    end

    it "a message without a file has no attachment_stable_url" do
      text = create(:message, conversation: conversation, user: seller)

      expect(thread_json.dig(text.id, "attachment_stable_url")).to be_nil
    end
  end

  path "/api/v1/conversations/{conversation_id}/messages/{id}/attachment" do
    parameter name: :conversation_id, in: :path, type: :integer
    parameter name: :id, in: :path, type: :integer

    get "a message's file (voice clip, photo, document)" do
      tags "Messages"
      description "1.2.1. A participant is redirected (302) to a fresh short-lived signed URL of the file, so the URL " \
                  "in the JSON never expires. Anyone else, a deleted message or a message without a file: 404."
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client, in: :header, type: :string, required: true
      parameter name: :uid, in: :header, type: :string, required: true
      let(:conversation_id) { conversation.id }
      let(:id) { voice.id }
      let(:as) { buyer }
      let(:"access-token") { auth_headers_for(as)["access-token"] }
      let(:client) { auth_headers_for(as)["client"] }
      let(:uid) { auth_headers_for(as)["uid"] }

      response "302", "a participant: redirected to the file" do
        run_test! { expect(response.location).to include("/rails/active_storage/") }
      end

      response "401", "signed out" do
        let(:"access-token") { nil }
        let(:client) { nil }
        let(:uid) { nil }

        run_test!
      end

      response "404", "not a participant (no existence leak)" do
        let(:as) { create(:user) }

        run_test!
      end

      response "404", "a deleted message" do
        let(:id) { create(:message, :voice, :deleted, conversation: conversation, user: seller).id }

        run_test!
      end

      response "404", "a message without a file" do
        let(:id) { create(:message, conversation: conversation, user: seller).id }

        run_test!
      end

      response "404", "a message of another conversation, through this one" do
        let(:id) do
          other = create(:conversation, buyer: buyer, listing: create(:listing, :active, user: seller))
          create(:message, :voice, conversation: other, user: seller).id
        end

        run_test!
      end
    end
  end
end
