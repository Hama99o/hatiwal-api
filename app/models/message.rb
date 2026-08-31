class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user
  # A meetup accept/decline points back to the proposal it answers.
  belongs_to :responds_to, class_name: "Message", optional: true

  has_one_attached :attachment

  enum :kind, {
    text: 0, meetup_proposal: 1, system: 2, offer: 3, document: 4, image_message: 5,
    meetup_accepted: 6, meetup_declined: 7, offer_accepted: 8, offer_declined: 9,
    offer_counter: 10
  }

  # Kinds that a client (request param) is allowed to set.
  # :system is intentionally excluded — only server-side code may persist system messages.
  # :offer_counter is sendable only by the seller (recipient of the original offer);
  # the buyer then responds using the existing offer_accepted / offer_declined kinds.
  USER_SENDABLE_KINDS = %w[
    text meetup_proposal meetup_accepted meetup_declined
    offer offer_accepted offer_declined document image_message offer_counter
  ].freeze

  validates :body, presence: true, length: { maximum: 1000 }

  # Chat attachments were unvalidated: `attachment` accepted any file of any
  # size. Documents are allowed as well as images because the :document message
  # kind exists and both pickers offer .pdf/.doc/.docx/.txt.
  MAX_ATTACHMENT_SIZE = 10.megabytes
  validates :attachment,
            attached_file: {
              types:    AttachedFileValidator::IMAGE_TYPES + AttachedFileValidator::DOCUMENT_TYPES,
              max_size: MAX_ATTACHMENT_SIZE
            }
  validate :kind_must_not_be_system_when_user_authored
  validate :responds_to_must_be_in_same_conversation, if: -> { responds_to_id.present? }

  # ── SF-B11: an offer carries how many units it is for ───────────────────────
  #
  # Before this, an offer was an amount and nothing else (the body encodes
  # "amount|currency|listedPrice", see MessageSerializer), so on a 15-bag listing
  # "I offer 12,000" could mean one bag or the lot, and the seller accepting it
  # was agreeing to a number whose meaning had never been stated. The buyer's own
  # stated quantity only ever existed as PROSE in the opening message (mobile's
  # `firstMessageQuantity.ts`: "the quantity is never persisted as structured
  # data anywhere"), so `Listing#units_for_sale` defaulted a batch sale to ONE
  # unit and the seller had to remember and re-type the agreed number. When they
  # didn't, `sold_units` moved by 1 instead of 3 and the listing advertised stock
  # it no longer had — docs/SPIKE_LISTING_QUANTITY.md's own top risk, "a stale
  # number lies to buyers", reached by a different route. The spike named this
  # fix and deferred it (§13.4: "the honest fix is a quantity on the offer — not
  # more copy").
  #
  # NULLABLE, NEVER DEFAULTED TO 1 — see the migration's note. `nil` means "the
  # sender said nothing", which every client reads as one unit; that is exactly
  # what every offer sent before today, and every offer on a single-item listing,
  # is. It is a DIFFERENT fact from a buyer explicitly asking for one, and only
  # keeping them apart lets a client decide whether to show an agreed quantity at
  # all.
  #
  # Wire code the client maps to its own en/ps/fa copy, for the same reason
  # Listing::QUANTITY_BELOW_SOLD_UNITS_CODE has one: `errors` is English Rails
  # prose and this app must never show an untranslated sentence to a Pashto or
  # Dari user.
  OFFER_QUANTITY_ABOVE_AVAILABLE      = :above_available_units
  OFFER_QUANTITY_ABOVE_AVAILABLE_CODE = "offer_quantity_above_available_units".freeze

  # Kinds that can carry an `offer_quantity` — the same pair MessageSerializer
  # already parses `offer_amount`/`offer_currency` out of. A counter is included
  # deliberately: a seller countering "3 for 40,000" has to be able to restate
  # how many, or the quantity is lost the moment either side moves the price.
  OFFER_KINDS = %i[offer offer_counter].freeze

  # Discarded rather than refused when it cannot mean anything — a single-item
  # listing, a non-offer kind, or a conversation whose listing is gone. That is
  # the rule `Listing#units_for_sale` and `#reserve_with_buyer!` already apply
  # ("a single-item listing ignores the param entirely"), and it is what keeps a
  # single-item listing byte-identical end to end: a stale or over-eager client
  # cannot invent a new 422 on a flow that works today.
  before_validation :discard_meaningless_offer_quantity

  # A positive integer when present. The `less_than_or_equal_to` ceiling is the
  # listing's own `available_units`, enforced below where the listing is in hand.
  validates :offer_quantity,
            numericality: { only_integer: true, greater_than: 0 },
            allow_nil: true
  validate :offer_quantity_within_available_units, if: -> { offer_quantity.present? }

  scope :ordered,      -> { order(:created_at) }            # chronological (oldest→newest)
  scope :newest_first, -> { order(created_at: :desc) }      # paginated chat: most recent page first
  scope :not_deleted,  -> { where(deleted_at: nil) }

  after_create :update_conversation_last_message_at

  def read?
    read_at.present?
  end

  def mark_read!
    update_column(:read_at, Time.current) if read_at.nil?
  end

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # SF-B11 — true for the kinds that may carry an `offer_quantity`. Replaces the
  # `offer? || offer_counter?` pair that MessageSerializer had written out twice
  # already (once per parsed offer field) — one predicate, one constant, so
  # "which kinds are offers" can never answer differently in two places.
  def offer_kind?
    OFFER_KINDS.include?(kind&.to_sym)
  end

  # SF-B11 — the machine-readable code for the validation errors currently on
  # this record, or nil. Same contract, and lives here for the same reason, as
  # `Listing#error_code`: the controller stays a two-liner and the code can never
  # drift from the validation that raises it.
  #
  # Only the available-units ceiling gets one. It is the single offer failure the
  # sender is expected to ACT on ("there are only 12 left, ask for 12"), so a
  # 3-locale client has to render it under the stepper in the user's own
  # language. Every other message 422 (blank body, a rejected kind, a
  # cross-conversation `responds_to_id`) keeps returning no `code` at all, which
  # is what it returned before this ticket.
  def error_code
    return OFFER_QUANTITY_ABOVE_AVAILABLE_CODE if errors.where(:offer_quantity, OFFER_QUANTITY_ABOVE_AVAILABLE).any?

    nil
  end

  private

  # Prevents any user-authored message from being stored with kind :system.
  # Server-generated system messages bypass this by setting user to a system
  # actor or by writing directly to the DB — not via the public API.
  def kind_must_not_be_system_when_user_authored
    errors.add(:kind, :invalid) if system?
  end

  # Ensures that the message being responded to belongs to the same conversation.
  # Without this guard, a participant of conversation A could link an
  # accept/decline response to a proposal in conversation B, corrupting
  # deal-outcome state across unrelated conversations.
  def responds_to_must_be_in_same_conversation
    referenced = Message.find_by(id: responds_to_id)
    if referenced.nil?
      errors.add(:responds_to_id, :invalid)
    elsif referenced.conversation_id != conversation_id
      errors.add(:responds_to_id, :invalid)
    end
  end

  def update_conversation_last_message_at
    conversation.update_column(:last_message_at, created_at)
  end

  # The listing this offer is about, or nil when the conversation's listing has
  # been removed (`Listing has_many :conversations, dependent: :nullify`, so
  # `conversation.listing_id` is legitimately nil on an orphaned thread).
  def offer_listing
    conversation&.listing
  end

  # SF-B11 — see the note on `before_validation :discard_meaningless_offer_quantity`.
  def discard_meaningless_offer_quantity
    return if offer_quantity.nil?
    return if offer_kind? && offer_listing&.multi_unit?

    self.offer_quantity = nil
  end

  # SF-B11 — an offer may never be for more units than the listing actually has
  # left AT THE MOMENT IT IS SENT.
  #
  # REFUSED, NOT CLAMPED. Everywhere else in this codebase a quantity the seller
  # types is clamped (`Listing#units_for_sale`, `#reserve_with_buyer!`) because
  # there the sale or the hold is a fact that already happened and refusing to
  # record it would lose it. An offer is the opposite: it is a proposal, nothing
  # has happened yet, and silently rewriting "I'll take 20" into "I'll take 12"
  # would hand the two of them a number neither one chose — in a marketplace with
  # no payment to arbitrate the difference, and where they find out at the
  # meetup. The sender is told the real ceiling instead.
  #
  # Worded to read correctly through `errors.full_messages`, which prefixes the
  # attribute name: "Offer quantity cannot be more than the 12 units still
  # available. Set it to 12 or fewer." Role-neutral ("Set it to"), because either
  # participant can send a counter.
  def offer_quantity_within_available_units
    available = offer_listing&.available_units
    return if available.nil? || offer_quantity <= available

    errors.add(:offer_quantity, OFFER_QUANTITY_ABOVE_AVAILABLE, message: too_many_units_message(available))
  end

  # `available.zero?` gets its own sentence: "cannot be more than the 0 units
  # still available. Set it to 0 or fewer." is nonsense, and a sold-out batch
  # whose thread is still open is a real state (a listing stays message-able
  # after it sells — only the stock is gone).
  def too_many_units_message(available)
    return "cannot be set — this listing has no units left." unless available.positive?

    "cannot be more than the #{available} #{'unit'.pluralize(available)} still available. " \
      "Set it to #{available} or fewer."
  end
end
