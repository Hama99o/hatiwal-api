require "swagger_helper"

# Documents the push-registration fields of PUT /api/v1/users/me — the ones
# the app uses to say whether it can receive notifications
# (docs/PUSH_NOTIFICATIONS.md). The endpoint accepts the other profile fields
# too; they are not described here.
RSpec.describe "Api::V1::Users::Profiles push registration", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  path "/api/v1/users/me" do
    put "report push registration (token, or why there is none)" do
      tags "Users"
      description "Send `push_token` once the app has one. When getting a token fails, send " \
                  "`push_registration_error` as \"<stage>: <message>\" (e.g. \"token: Default FirebaseApp is " \
                  "not initialized\"). The server keeps the last error only, strips control characters, caps " \
                  "it at 300 characters, and clears it when a token is saved. A blank string clears it too.\n\n" \
                  "OFFLINE §10.2 — `user.base` (optional): for the fields a person edits by hand (firstname, " \
                  "lastname, phone, bio, city, province, whatsapp_number), the value the client saw. One changed " \
                  "elsewhere meanwhile is not overwritten: the rest applies and the answer is 409 " \
                  "`code: \"edit_conflict\"` + `fields`. Prefs and the push fields never conflict."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            properties: {
              push_token: { type: :string, maxLength: 200, example: "ExponentPushToken[xxxxxxxx]" },
              push_registration_error: { type: :string, maxLength: 300,
                                         example: "token: Default FirebaseApp is not initialized" },
              base: { type: :object, additionalProperties: true,
                      description: "OFFLINE §10.2 — per hand-edited field sent, the value the client saw" }
            }
          }
        },
        required: [ "user" ]
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      parameter name: :"Idempotency-Key", in: :header, type: :string, required: false,
                description: "OFFLINE §10.1 — 8 to 64 letters, digits, - or _. A retry with the same key " \
                             "replays the first answer (one write); the same key with another body → 422."
      let(:"Idempotency-Key") { nil }

      response "200", "stored; a reported error is kept until a token arrives" do
        let(:body) { { user: { push_registration_error: "token: Default FirebaseApp is not initialized" } } }

        run_test! do
          expect(user.reload.push_registration_error).to eq("token: Default FirebaseApp is not initialized")
        end
      end

      response "409", "OFFLINE §10.2 — a hand-edited field changed elsewhere since the client saw it" do
        let(:body) { { user: { bio: "Mine", city: "Herat", base: { bio: "Old", city: "Kabul" } } } }

        before { user.update!(bio: "Theirs", city: "Kabul") }

        run_test! do |response|
          json = JSON.parse(response.body)
          expect(json["code"]).to eq("edit_conflict")
          expect(json["fields"].keys).to eq([ "bio" ])
          expect(user.reload.city).to eq("Herat")
        end
      end

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        let(:body)           { { user: { push_token: "ExponentPushToken[x]" } } }

        run_test!
      end
    end
  end
end
