namespace :db do
  namespace :seed do
    desc "Seed QA data for LOC-1 / VER-1 (users per province, guessed locations, verification requests). Idempotent; creates no Support threads."
    task qa_features: :environment do
      load Rails.root.join("db/seeds/qa_features.rb")
    end
  end
end
