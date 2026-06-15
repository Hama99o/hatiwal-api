namespace :db do
  namespace :seed do
    desc "Seed E2E test data — creates known test accounts and listings for Maestro flows"
    task e2e: :environment do
      load Rails.root.join("db/seeds/e2e.rb")
    end

    desc "Reset E2E test data — wipes all e2e accounts and re-seeds from scratch"
    task reset_e2e: :environment do
      E2E_EMAILS = %w[
        buyer@hatiwal.test
        seller@hatiwal.test
        newbuyer@hatiwal.test
      ].freeze

      puts "=== Wiping E2E test data ==="

      users = User.where(email: E2E_EMAILS)

      # Destroy in order to respect foreign keys
      user_ids = users.pluck(:id)

      Report.where(reporter_id: user_ids).delete_all
      SavedListing.where(user_id: user_ids).delete_all

      Message.joins(:conversation)
             .where(conversations: { buyer_id: user_ids })
             .or(Message.joins(:conversation).where(conversations: { seller_id: user_ids }))
             .delete_all

      Conversation.where(buyer_id: user_ids).or(Conversation.where(seller_id: user_ids)).delete_all

      Listing.where(user_id: user_ids).delete_all

      users.delete_all

      puts "  wiped #{E2E_EMAILS.length} users and all associated data"
      puts ""

      load Rails.root.join("db/seeds/e2e.rb")
    end
  end
end
