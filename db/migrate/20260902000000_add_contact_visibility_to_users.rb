class AddContactVisibilityToUsers < ActiveRecord::Migration[8.0]
  def change
    # A SEPARATE WhatsApp number, because it is often not the account phone.
    #
    # Owner request, 2026-09-02: "add input in backend also and web edit and
    # mobile edit to add whatsapp number also… and give posibilites to add same
    # number as whatapp option also". The "same number" convenience lives in the
    # clients (a toggle that copies `phone` into this field); the column stays a
    # plain independent value so a seller whose WhatsApp is on a different SIM is
    # representable at all.
    add_column :users, :whatsapp_number, :string

    # Per-user control over what buyers can see.
    #
    # Defaults preserve today's behaviour EXACTLY rather than quietly changing
    # what is already published:
    #   - phone is already revealed to buyers through the gated two-tap
    #     SellerPhoneReveal on a listing, so this defaults to true; turning it
    #     off is the new capability.
    #   - the user's own city/province is likewise already in the :public view,
    #     so it defaults to true too.
    # A migration that flipped either to false would silently remove a working
    # feature from every existing seller.
    add_column :users, :show_phone_publicly, :boolean, default: true, null: false
    add_column :users, :show_address_publicly, :boolean, default: true, null: false
  end
end
