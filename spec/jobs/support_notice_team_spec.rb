require "rails_helper"

# SHOP-3 team events → a Support message in the person's language (owner,
# 2026-10-07: "the same system as for users, for joining a shop"). Each kind is
# driven by the real action, then the queued SupportNoticeJob is run.
RSpec.describe "Support notices for shop team events", type: :job do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let(:owner) { create(:user, :confirmed, firstname: "Tamana", lastname: "Owner", preferred_language: "en") }
  let(:shop) { create(:shop, owner: owner, name: "Kabul Cosmetics") }

  def notices_for(user) = Conversation.kind_support.find_by(buyer_id: user.id)&.messages.to_a.map(&:body)

  def run_support_jobs
    perform_enqueued_jobs(only: SupportNoticeJob)
  end

  it "the invited (confirmed) account is told who invited them, as what, and where to answer" do
    invitee = create(:user, :confirmed, firstname: "Gul", email: "gul@hatiwal.test", preferred_language: "ps")
    shop.invite!(by: owner, email: "gul@hatiwal.test")
    run_support_jobs

    expect(notices_for(invitee)).to eq([ I18n.t("support.notices.shop_invite_received", locale: :ps, name: "Gul",
                                                  inviter: "Tamana Owner", shop: "Kabul Cosmetics",
                                                  role: I18n.t("support.team_roles.staff", locale: :ps)) ])
  end

  it "joining tells the owner who joined, and welcomes the new member" do
    member = create(:user, :confirmed, firstname: "Ali", lastname: "Khan", preferred_language: "fa")
    create(:shop_invite, shop: shop).accept!(member)
    run_support_jobs

    expect(notices_for(owner)).to eq([ "Ali Khan joined Kabul Cosmetics as Staff." ])
    expect(notices_for(member)).to eq([ I18n.t("support.notices.shop_joined", locale: :fa, shop: "Kabul Cosmetics") ])
  end

  it "a role change names the new role in the member's language" do
    member = create(:user, preferred_language: "ur").tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    shop.change_role!(member, role: "manager", by: owner)
    run_support_jobs

    expect(notices_for(member)).to eq([ "#{shop.name} میں آپ کا کردار اب مینیجر ہے۔" ])
  end

  it "removal tells the removed person; leaving on your own sends nothing" do
    removed = create(:user, preferred_language: "en").tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    leaver = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    shop.remove_team_member!(removed, by: owner)
    shop.leave!(leaver)
    run_support_jobs

    expect(notices_for(removed)).to eq([ "You're no longer on Kabul Cosmetics's team. You sell as yourself again." ])
    expect(notices_for(leaver)).to be_blank
  end

  it "a transfer tells the new owner and the old owner (now Manager)" do
    heir = create(:user, firstname: "Mina", lastname: "Heir", preferred_language: "en").tap { |u| shop.shop_members.create!(user: u, role: :manager) }
    shop.transfer_ownership!(heir, by: owner)
    run_support_jobs

    expect(notices_for(heir)).to eq([ "Tamana Owner handed Kabul Cosmetics to you. You are now its owner." ])
    expect(notices_for(owner)).to eq([ "You handed Kabul Cosmetics to Mina Heir. You stay on the team as Manager." ])
  end

  it "sends nothing when the state changed before the job ran (invite cancelled, member gone)" do
    invitee = create(:user, :confirmed, email: "late@hatiwal.test")
    invite = shop.invite!(by: owner, email: "late@hatiwal.test")
    invite.update!(status: :cancelled)
    member = create(:user, preferred_language: "en").tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    shop.change_role!(member, role: "manager", by: owner)
    shop.remove_team_member!(member, by: owner)
    run_support_jobs

    expect(notices_for(invitee)).to be_blank
    expect(notices_for(member)).to eq([ "You're no longer on Kabul Cosmetics's team. You sell as yourself again." ])
  end

  it "posts once on a retried job, and follows the Support gate" do
    member = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    2.times { SupportNoticeJob.perform_now(member.id, "shop_joined", shop.id, {}) }
    expect(notices_for(member).size).to eq(1)

    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("false")
    stranger = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
    SupportNoticeJob.perform_now(stranger.id, "shop_joined", shop.id, {})
    expect(notices_for(stranger)).to be_blank # no thread yet and the gate is off
  end

  it "has every team notice and role in all four locales, with the same placeholders" do
    keys = SupportNoticeJob::TEAM_NOTICES.keys
    User::SUPPORTED_LANGUAGES.each do |locale|
      keys.each do |key|
        en = I18n.t("support.notices.#{key}", locale: :en, raise: true).scan(/%\{\w+\}/).sort
        text = I18n.t("support.notices.#{key}", locale: locale, raise: true)
        expect(text.scan(/%\{\w+\}/).sort).to eq(en), "#{locale}.#{key}"
      end
      %w[owner manager staff].each { |role| expect(I18n.t("support.team_roles.#{role}", locale: locale, raise: true)).to be_present }
    end
    expect(I18n.t("support.notices.shop_joined", locale: :ps, shop: "x")).to include("ښه راغلاست")
  end
end
