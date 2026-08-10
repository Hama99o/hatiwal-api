namespace :transactions do
  desc "Recompute every user's sold_count / bought_count from the transactions " \
       "table (TASK-TX02 safety net) — run this if the denormalized counters " \
       "ever drift, e.g. after an admin edits a Listing's status directly via " \
       "the Administrate dashboard (ListingDashboard::FORM_ATTRIBUTES permits " \
       ":status, bypassing Listing#sold_with_buyer!/#sold! and the normal " \
       "counter bump). Safe to run any time — fully idempotent."
  task recompute_counters: :environment do
    count = 0
    User.find_each do |user|
      user.recompute_transaction_counters!
      count += 1
    end
    puts "Recomputed sold_count/bought_count for #{count} users."
  end
end
