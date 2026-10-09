require "rails_helper"

# Owner gap, 2026-10-08: an admin suspending (or reactivating) a shop told
# no one — the shop just left search. Now: a Support notice in the SHOP's
# thread (its whole team reads it), with the admin's reason when given, in the
# reader's language; and a push to the owner and the managers (not Staff),
# as the team push the apps already handle (shop_membership_changed: they
# refetch who they are and drop a suspended shop back to Me).
RSpec.describe "Shop suspended / reactivated notice", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let(:shop) { create(:shop) }
  let(:owner) { shop.owner.tap { |u| u.update!(preferred_language: "ps", push_token: "ExponentPushToken[owner]") } }
  let(:manager) { create(:user, :confirmed, preferred_language: "fa", push_token: "ExponentPushToken[mgr]") }
  let(:staff) { create(:user, :confirmed, push_token: "ExponentPushToken[staff]") }

  before do
    owner
    shop.shop_members.create!(user: manager, role: :manager)
    shop.shop_members.create!(user: staff, role: :staff)
    sign_in admin, scope: :admin_user
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
    allow(Notifications::ExpoPushService).to receive(:deliver).and_return(double(error: nil))
  end

  def shop_thread_messages
    Conversation.admin_shop_support_thread_for(shop)&.messages&.order(:id) || Message.none
  end

  def pushed_tokens
    tokens = []
    expect(Notifications::ExpoPushService).to have_received(:deliver).at_least(:once) do |**args|
      tokens << args
    end
    tokens
  rescue RSpec::Expectations::ExpectationNotMetError
    []
  end

  it "suspended with a reason: one notice in the shop's thread (owner's language, with the reason), a push to the owner and the manager only" do
    perform_enqueued_jobs do
      patch "/admin/shops/#{shop.id}/suspend", params: { reason: "Fake products reported" }
    end
    expect(shop.reload).to be_suspended
    notice = shop_thread_messages.last
    expect(notice).to be_present
    expect(notice.body).to include(shop.name).and include("Fake products reported")
    expect(notice.body).to eq(I18n.t("support.notices.shop_suspended_reason", locale: :ps, name: owner.firstname, shop: shop.name, reason: "Fake products reported"))

    sent = []
    expect(Notifications::ExpoPushService).to have_received(:deliver).twice do |**args|
      sent << args
    end
    expect(sent.map { |a| a[:token] }).to contain_exactly("ExponentPushToken[owner]", "ExponentPushToken[mgr]")
    expect(sent.map { |a| a[:data] }).to all(include(type: "shop_membership_changed", reason: "suspended", shopId: shop.id))
    fa = sent.find { |a| a[:token] == "ExponentPushToken[mgr]" }
    expect(fa[:body]).to eq(I18n.t("push.shop_team.shop_membership_changed_suspended", locale: :fa, shop: shop.name, name: ""))
  end

  it "suspended without a reason: the plain notice" do
    perform_enqueued_jobs { patch "/admin/shops/#{shop.id}/suspend" }
    expect(shop_thread_messages.last.body).to eq(I18n.t("support.notices.shop_suspended", locale: :ps, name: owner.firstname, shop: shop.name))
  end

  it "reactivated: a notice with a button to the shop, and the same two pushes" do
    shop.suspend!
    perform_enqueued_jobs { patch "/admin/shops/#{shop.id}/reactivate" }
    notice = shop_thread_messages.last
    expect(notice.body).to eq(I18n.t("support.notices.shop_reactivated", locale: :ps, name: owner.firstname, shop: shop.name))
    expect(notice.context.dig("action", "params")).to eq("shop_id" => shop.id)
    expect(Notifications::ExpoPushService).to have_received(:deliver).twice
  end

  it "a suspension undone before its job runs is not announced (the notice must still be true); the reactivation is" do
    patch "/admin/shops/#{shop.id}/suspend"
    shop.reload.reactivate!
    perform_enqueued_jobs(only: SupportNoticeJob)
    expect(shop_thread_messages.pluck(:body)).to eq([ I18n.t("support.notices.shop_reactivated", locale: :ps, name: owner.firstname, shop: shop.name) ])
  end

  it "the texts exist in all 4 locales with the same placeholders" do
    %w[support.notices.shop_suspended support.notices.shop_suspended_reason support.notices.shop_reactivated
       push.shop_team.shop_membership_changed_suspended push.shop_team.shop_membership_changed_reactivated].each do |key|
      en = I18n.t(key, locale: :en, raise: true).scan(/%\{\w+\}/).sort
      %i[ps fa ur].each do |locale|
        str = I18n.t(key, locale: locale, raise: true)
        expect(str.scan(/%\{\w+\}/).sort).to eq(en), "#{key} #{locale}"
        expect(str.gsub(/%\{\w+\}/, "").scan(/[A-Za-z]{3,}/) - %w[Hatiwal]).to be_empty, "#{key} #{locale}: #{str}"
      end
    end
  end
end
