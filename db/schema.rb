# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_20_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_admin_users_on_unlock_token", unique: true
  end

  create_table "blocks", force: :cascade do |t|
    t.bigint "blocked_id", null: false
    t.bigint "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_blocks_on_blocker_id"
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name_en", null: false
    t.string "name_fa", null: false
    t.string "name_ps", null: false
    t.bigint "parent_id"
    t.integer "position", default: 0
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_categories_on_active"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.index ["position"], name: "index_categories_on_position"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "buyer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.bigint "listing_id", null: false
    t.bigint "seller_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_conversations_on_buyer_id"
    t.index ["last_message_at"], name: "index_conversations_on_last_message_at"
    t.index ["listing_id", "buyer_id"], name: "index_conversations_on_listing_id_and_buyer_id", unique: true
    t.index ["listing_id"], name: "index_conversations_on_listing_id"
    t.index ["seller_id"], name: "index_conversations_on_seller_id"
    t.index ["status"], name: "index_conversations_on_status"
  end

  create_table "listing_price_histories", force: :cascade do |t|
    t.datetime "changed_at", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.bigint "listing_id", null: false
    t.decimal "new_price", precision: 12, scale: 2, null: false
    t.decimal "old_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["changed_at"], name: "index_listing_price_histories_on_changed_at"
    t.index ["listing_id"], name: "index_listing_price_histories_on_listing_id"
  end

  create_table "listing_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_viewed_at", null: false
    t.bigint "listing_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["listing_id"], name: "index_listing_views_on_listing_id"
    t.index ["user_id", "listing_id"], name: "index_listing_views_on_user_id_and_listing_id", unique: true
    t.index ["user_id"], name: "index_listing_views_on_user_id"
  end

  create_table "listings", force: :cascade do |t|
    t.string "address"
    t.bigint "category_id", null: false
    t.integer "condition"
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.text "description"
    t.datetime "expires_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.string "location"
    t.decimal "longitude", precision: 10, scale: 6
    t.decimal "price", precision: 12, scale: 2, null: false
    t.datetime "published_at"
    t.datetime "reserved_at"
    t.datetime "sold_at"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["category_id"], name: "index_listings_on_category_id"
    t.index ["condition"], name: "index_listings_on_condition"
    t.index ["created_at"], name: "index_listings_on_created_at"
    t.index ["expires_at"], name: "index_listings_on_expires_at"
    t.index ["price"], name: "index_listings_on_price"
    t.index ["status", "created_at"], name: "index_listings_on_status_and_created_at"
    t.index ["status"], name: "index_listings_on_status"
    t.index ["user_id"], name: "index_listings_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "read_at"
    t.bigint "responds_to_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["read_at"], name: "index_messages_on_read_at"
    t.index ["responds_to_id"], name: "index_messages_on_responds_to_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "reason", null: false
    t.bigint "reportable_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reporter_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_reports_on_reportable"
    t.index ["reporter_id", "reportable_type", "reportable_id"], name: "idx_reports_unique_per_reporter", unique: true
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["status"], name: "index_reports_on_status"
  end

  create_table "saved_listings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "listing_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["listing_id"], name: "index_saved_listings_on_listing_id"
    t.index ["user_id", "listing_id"], name: "index_saved_listings_on_user_id_and_listing_id", unique: true
    t.index ["user_id"], name: "index_saved_listings_on_user_id"
  end

  create_table "saved_searches", force: :cascade do |t|
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.float "latitude"
    t.string "location"
    t.float "longitude"
    t.integer "price_max"
    t.integer "price_min"
    t.integer "radius"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_saved_searches_on_category_id"
    t.index ["user_id", "created_at"], name: "index_saved_searches_user_recent"
    t.index ["user_id"], name: "index_saved_searches_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "allow_password_change", default: false
    t.string "bio"
    t.string "block_reason"
    t.string "city"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "firstname", default: "", null: false
    t.string "image"
    t.string "lastname", default: "", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.datetime "locked_at"
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name"
    t.string "nickname"
    t.string "phone"
    t.string "preferred_language", default: "ps"
    t.string "preferred_theme", default: "system"
    t.string "provider", default: "email", null: false
    t.string "province"
    t.string "push_token"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "seller_mode", default: false, null: false
    t.integer "status", default: 0, null: false
    t.json "tokens"
    t.string "uid", default: "", null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.index ["city"], name: "index_users_on_city"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blocks", "users", column: "blocked_id"
  add_foreign_key "blocks", "users", column: "blocker_id"
  add_foreign_key "categories", "categories", column: "parent_id", on_delete: :restrict
  add_foreign_key "conversations", "listings"
  add_foreign_key "conversations", "users", column: "buyer_id"
  add_foreign_key "conversations", "users", column: "seller_id"
  add_foreign_key "listing_price_histories", "listings"
  add_foreign_key "listing_views", "listings"
  add_foreign_key "listing_views", "users"
  add_foreign_key "listings", "categories"
  add_foreign_key "listings", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "messages", column: "responds_to_id"
  add_foreign_key "messages", "users"
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "saved_listings", "listings"
  add_foreign_key "saved_listings", "users"
  add_foreign_key "saved_searches", "categories"
  add_foreign_key "saved_searches", "users"
end
