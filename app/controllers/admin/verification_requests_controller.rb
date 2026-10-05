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
      @kind = params[:kind] == "shops" ? "shops" : "users"
      requests = VerificationRequest.for_users.where.not(status: :cancelled)
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
      @same_number = @verification.same_number_elsewhere.limit(10).to_a
      @history = @user.verification_requests.where.not(id: @verification.id).recent.includes(:decided_by)
      @audit = AdminAuditLog.where(target: @verification).recent.includes(:admin_user).limit(30)
    end

    def approve
      @verification.approve!(admin: current_admin_user, checklist: params[:checklist] || {})
      log_admin_action("verification_approve", target: @verification, details: checklist_summary)
      redirect_to next_waiting_path, notice: "#{@verification.subject.full_name} is verified. They get a message in their language."
    rescue ArgumentError => e
      redirect_to admin_verification_request_path(@verification), alert: e.message
    end

    def reject
      @verification.reject!(admin: current_admin_user, reason_code: params[:reason_code],
                       reason_text: params[:reason_text], checklist: params[:checklist] || {})
      log_admin_action("verification_reject", target: @verification, details: reason_details)
      redirect_to next_waiting_path, notice: "Request rejected. #{@verification.subject.full_name} sees the reason and can try again."
    rescue ArgumentError => e
      redirect_to admin_verification_request_path(@verification), alert: e.message
    end

    def revoke
      @verification.revoke!(admin: current_admin_user, reason_code: params[:reason_code], reason_text: params[:reason_text])
      log_admin_action("verification_revoke", target: @verification, details: reason_details)
      redirect_to admin_verification_request_path(@verification), notice: "Badge removed. #{@verification.subject.full_name} gets a message with the reason."
    rescue ArgumentError => e
      redirect_to admin_verification_request_path(@verification), alert: e.message
    end

    # From the user's admin page: remove a badge, whether or not an approved
    # request is behind it.
    def revoke_badge
      user = User.find(params[:user_id])
      return redirect_to(admin_user_path(user), alert: "#{user.full_name} is not verified.") unless user.verified?

      @verification = VerificationRequest.revoke_badge!(user, admin: current_admin_user,
                                                        reason_code: params[:reason_code], reason_text: params[:reason_text])
      log_admin_action("verification_revoke", target: @verification, details: reason_details)
      redirect_to admin_user_path(user), notice: "Badge removed. #{user.full_name} gets a message with the reason."
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

    def set_request
      @verification = VerificationRequest.for_users.includes(:subject).find(params[:id])
    end

    # After a decision, straight on to the next one waiting (queue flow).
    def next_waiting_path
      following = VerificationRequest.for_users.requested.where.not(id: @verification.id).order(:created_at).first
      following ? admin_verification_request_path(following) : admin_verification_requests_path
    end

    def checklist_summary
      ticked = @verification.checklist.select { |_, v| v }.keys
      ticked.any? ? "checklist: #{ticked.join(', ')}" : "checklist: none ticked"
    end

    def reason_details
      [ @verification.reason_code, @verification.reason_text ].compact_blank.join(": ")
    end
  end
end
