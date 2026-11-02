namespace :prohibited_terms do
  desc "Add the missing terms of config/prohibited_terms.yml (never edits or deletes; re-adds a term deleted since)"
  task seed: :environment do
    puts "prohibited_terms: #{ProhibitedTerm.seed_defaults!} added, #{ProhibitedTerm.count} in total"
  end
end
