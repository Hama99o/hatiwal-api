# VER-1: the verification queue (Klaviyo moderation pattern). An admin looks at
# the photos side by side, ticks the checklist and approves or rejects BY HAND.
# Spec: hatiwal-mobile/docs/VERIFICATION.md "Admin: the verification queue".
#
# Hand-built like SupportConversationsController: a decision card, not a CRUD
# table. The decisions live on VerificationRequest; this only orchestrates and
# audit-logs.
#
# Documents: the show page renders <img> tags pointing at #document with a
# token that expires in VerificationRequest::DOCUMENT_URL_TTL. Each file served
# is written to AdminAuditLog FIRST — if the log cannot be written, the file is
# not served.
module Admin
  class VerificationRequestsController < Admin::ApplicationController
    PER_PAGE = 25
    FILTERS = {
      "waiting" => :requested,
      "approved" => :approved,
      "rejected" => :rejected,
      "revoked" => :revoked,
      "all" => nil
    }.freeze

    before_action :set_request, only: %i[show approve reject revoke document reveal_number]

    def index
      @filter = FILTERS.key?(params[:status]) ? params[:status] : "waiting"
      # Waiting count on each kind tab, so a shop request is never missed behind the Users tab.
      @waiting_by_kind = { "users" => VerificationRequest.for_users.requested.count,
                           "shops" => VerificationRequest.for_shops.requested.count }
      # No kind asked (the nav link): open where the work is.
      @kind = params[:kind].presence_in(%w[users shops]) ||
              (@waiting_by_kind["users"].zero? && @waiting_by_kind["shops"].positive? ? "shops" : "users")
      # SHOP-1: the Shops tab is live.
      requests = (@kind == "shops" ? VerificationRequest.for_shops : VerificationRequest.for_users).where.not(status: :cancelled)
      @counts = FILTERS.transform_values { |status| status ? requests.where(status: status).count : requests.count }
      status = FILTERS[@filter]
      requests = requests.where(status: status) if status
      # Waiting: oldest first (first come, first served). Decided: newest first.
      requests = @filter == "waiting" ? requests.order(:created_at) : requests.order(Arel.sql("COALESCE(decided_at, created_at) DESC"))
      @requests = requests.includes(:subject, :decided_by).page(params[:page]).per(PER_PAGE)
    end

    def show
      @user = @verification.subject
      # Same ID number on another account (owner decision): flagged here only.
      # SHOP-2: also the same proof file; never the applicant's own other requests.
      duplicates = @verification.duplicates_elsewhere
      @same_number = duplicates[:number]
      @same_proof = duplicates[:proof]
      @history = @user.verification_requests.where.not(id: @verification.id).recent.includes(:decided_by)
      @audit = AdminAuditLog.where(target: @verification).recent.includes(:admin_user).limit(30)
    end

    def approve
      @verification.approve!(admin: current_admin_user, checklist: params[:checklist] || {})
      log_admin_action("verification_approve", target: @verification, details: checklist_summary)
      redirect_to next_waiting_path, notice: "#{@verification.subject.full_name} is verified. #{message_outcome}#{next_note}"
    rescue ArgumentError => e
      redirect_to admin_verification_request_path(@verification), alert: e.message
    end

    # Owner, 2026-10-12 (item 8): a missing reason (or "Other" without its text)
    # comes back to the same page as a clear error at the field, with the
    # checklist and what was typed kept — never a crash or a blank 422.
    def reject
      problem = reason_problem(@verification.reject_reasons)
      return render_decision_problem(:reject, problem) if problem

      @verification.reject!(admin: current_admin_user, reason_code: params[:reason_code],
                       reason_text: params[:reason_text], checklist: params[:checklist] || {})
      log_admin_action("verification_reject", target: @verification, details: reason_details)
      redirect_to next_waiting_path, notice: "Request rejected. #{@verification.subject.full_name} sees the reason and can try again. #{message_outcome}#{next_note}"
    rescue ArgumentError => e
      render_decision_problem(:reject, { field: :base, message: e.message })
    end

    def revoke
      problem = reason_problem(VerificationRequest::REVOKE_REASONS)
      return render_decision_problem(:revoke, problem) if problem

      @verification.revoke!(admin: current_admin_user, reason_code: params[:reason_code], reason_text: params[:reason_text])
      log_admin_action("verification_revoke", target: @verification, details: reason_details)
      redirect_to admin_verification_request_path(@verification), notice: "Badge removed. #{message_outcome}"
    rescue ArgumentError => e
      render_decision_problem(:revoke, { field: :base, message: e.message })
    end

    # From the user's admin page: remove a badge, whether or not an approved
    # request is behind it.
    def revoke_badge
      user = User.find(params[:user_id])
      return redirect_to(admin_user_path(user), alert: "#{user.full_name} is not verified.") unless user.verified?

      problem = VerificationRequest.reason_problem(params[:reason_code], params[:reason_text],
                                                   VerificationRequest::REVOKE_REASONS, person: user.full_name)
      return redirect_to(admin_user_path(user, anchor: "revoke-badge"), alert: "Badge not removed: #{problem[:message]}") if problem

      @verification = VerificationRequest.revoke_badge!(user, admin: current_admin_user,
                                                        reason_code: params[:reason_code], reason_text: params[:reason_text])
      log_admin_action("verification_revoke", target: @verification, details: reason_details)
      redirect_to admin_user_path(user), notice: "Badge removed. #{message_outcome}"
    rescue ArgumentError => e
      redirect_to admin_user_path(user), alert: e.message
    end

    # POST /admin/verification_requests/:id/reveal_number — the full ID number,
    # for this request only. Logged first; never cached.
    def reveal_number
      AdminAuditLog.record!(admin_user: current_admin_user, action: "verification_number_view", target: @verification)
      response.headers["Cache-Control"] = "no-store, private"
      @revealed_number = @verification.document_number
      show
      render :show
    end

    # GET /admin/verification_requests/:id/document/:token — one ID photo.
    def document
      blob = @verification.blob_for_token(params[:token])
      return head(:not_found) unless blob

      name = @verification.attached_files.find { |n| @verification.public_send(n).blob.id == blob.id }
      AdminAuditLog.record!(admin_user: current_admin_user, action: "verification_document_view",
                            target: @verification, details: name.to_s)
      response.headers["Cache-Control"] = "no-store, private"
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_data blob.download, type: blob.content_type, disposition: "inline", filename: "#{name}#{blob.filename.extension_with_delimiter}"
    rescue ActiveStorage::FileNotFoundError
      head :not_found
    end

    private

    def reason_problem(allowed)
      VerificationRequest.reason_problem(params[:reason_code], params[:reason_text], allowed,
                                         person: @verification.subject.verification_notice_recipient.full_name)
    end

    # The same page, with the error at its field and what was typed kept (422).
    def render_decision_problem(action, problem)
      @decision_error = problem.merge(action: action)
      flash.now[:alert] = problem[:message]
      show
      render :show, status: :unprocessable_entity
    end

    # The queue flow: say where the admin landed after a decision.
    def next_note
      following = VerificationRequest.where(subject_type: @verification.subject_type).requested.where.not(id: @verification.id).exists?
      following ? " Next request opened." : " No more waiting."
    end

    def set_request
      @verification = VerificationRequest.includes(:subject).find(params[:id])
    end

    # After a decision, straight on to the next one waiting (queue flow).
    def next_waiting_path
      following = VerificationRequest.where(subject_type: @verification.subject_type).requested
                                     .where.not(id: @verification.id).order(:created_at).first
      following ? admin_verification_request_path(following) : admin_verification_requests_path(kind: kind_of(@verification))
    end

    def kind_of(verification) = verification.shop_subject? ? "shops" : "users"

    # Says whether the Support message really goes out — the gate
    # (Conversation.admin_message_refusal) can hold it back, and the flash must
    # never claim a message that will not be sent.
    def message_outcome
      recipient = @verification.subject.verification_notice_recipient
      refusal = Conversation.admin_message_refusal(recipient)
      return "No Support message sent to #{recipient.full_name}: #{refusal}." if refusal

      "#{recipient.full_name} gets a Support message in #{language_name(recipient)}."
    end

    def language_name(user)
      { "en" => "English", "ps" => "Pashto", "fa" => "Dari", "ur" => "Urdu" }.fetch(user.preferred_language.to_s, "English")
    end
    helper_method :kind_of

    def checklist_summary
      ticked = @verification.checklist.select { |_, v| v }.keys
      ticked.any? ? "checklist: #{ticked.join(', ')}" : "checklist: none ticked"
    end

    def reason_details
      [ @verification.reason_code, @verification.reason_text ].compact_blank.join(": ")
    end
  end
end
