# UPD-1 — "App versions": the force-update / update-reminder settings, who is
# on which build, and the "please update" message for builds too old to block
# (hatiwal-mobile/docs/FORCE_UPDATE.md). Every change is audit-logged.
module Admin
  class AppVersionsController < Admin::ApplicationController
    PERMITTED = AppReleaseSetting::PLATFORMS.flat_map { |p| AppReleaseSetting::FIELDS.map { |f| :"#{p}_#{f}" } }.freeze
    # A new minimum blocking at least this share of reported users asks twice.
    MASS_BLOCK_SHARE = 0.9

    def show
      @setting = AppReleaseSetting.current
      load_usage
    end

    def update
      @setting = AppReleaseSetting.current
      @setting.assign_attributes(params.require(:app_release_setting).permit(*PERMITTED))
      @setting.updated_by = current_admin_user
      changes = @setting.changes_to_save.except("updated_by_id")
      load_usage

      unless @setting.valid?
        flash.now[:alert] = @setting.errors.full_messages.to_sentence
        return render :show, status: :unprocessable_entity
      end

      @raised = @setting.raised_minimums
      if @raised.any? && params[:confirm_raise] != "1"
        flash.now[:alert] = "Confirm: this raises the minimum and blocks the users counted below."
        return render :show, status: :unprocessable_entity
      end
      # Typo guard: a minimum that blocks almost everyone (released=1.1.70 and
      # min=1.1.70 in one save) needs a SECOND, explicit confirmation.
      @mass_block = @raised.select { |p| @affected[p][:blocked_share] >= MASS_BLOCK_SHARE }
      if @mass_block.any? && params[:confirm_mass_block] != "1"
        flash.now[:alert] = "This minimum blocks #{@mass_block.map { |p| "#{@affected[p][:blocked_percent]}% of #{label(p)}" }.to_sentence} " \
                            "users who reported a version. Check for a typo, then confirm a second time."
        return render :show, status: :unprocessable_entity
      end

      @setting.save!
      log_admin_action("app_versions_update", target: @setting,
                                              details: [ changes.map { |k, (a, b)| "#{k}: #{a.presence || '—'} → #{b.presence || '—'}" }.join(", "),
                                                         params[:note].presence ].compact.join(" · "))
      redirect_to admin_app_versions_path, notice: "App versions saved. Apps pick it up within a minute."
    end

    def message_old_versions
      platform = params[:platform].to_s
      target = params[:target_version].to_s.strip
      setting = AppReleaseSetting.current
      released = AppReleaseSetting::PLATFORMS.include?(platform) ? setting.public_send(:"#{platform}_released_version") : nil
      if released.blank? || !AppVersion.valid?(target) || AppVersion.below?(released, target)
        return redirect_to admin_app_versions_path, alert: "#{target.presence || 'That version'} is not released for #{label(platform)}: nobody could update to it."
      end

      queued = AppUpdateNotice.notify_old_versions!(platform: platform, target: target)
      log_admin_action("app_update_message", target: setting, details: "#{platform} below #{target}: #{queued} queued")
      redirect_to admin_app_versions_path, notice: "#{queued} users on #{platform} below #{target} get the update message in their language."
    rescue ArgumentError => e
      redirect_to admin_app_versions_path, alert: e.message
    end

    private

    # { "ios" => { "1.1.4" => 120, … }, … } in ONE grouped query, and the
    # "blocking below <min> affects N" numbers computed from it in Ruby.
    def load_usage
      counts = User.members.where(deleted_at: nil).where.not(last_app_version: nil)
                   .group(:last_app_platform, :last_app_version).count
      @usage = AppReleaseSetting::PLATFORMS.index_with do |platform|
        counts.select { |(p, _v), _n| p == platform }
              .to_h { |(_p, v), n| [ v, n ] }
              .sort_by { |v, _n| AppVersion.parse(v) || [] }.reverse.to_h
      end
      @legacy_count = User.members.where(deleted_at: nil, last_app_version: nil).where.not(legacy_client_seen_at: nil).count
      @affected = AppReleaseSetting::PLATFORMS.index_with do |platform|
        min = @setting.public_send(:"#{platform}_min_version")
        latest = @setting.public_send(:"#{platform}_latest_version")
        total = @usage.fetch(platform).values.sum
        blocked = below_count(platform, min)
        share = total.zero? ? 0.0 : blocked.to_f / total
        { blocked: blocked, reminded: below_count(platform, latest) - blocked,
          blocked_share: share, blocked_percent: (share * 100).round }
      end
    end

    def label(platform) = platform == "ios" ? "iOS" : "Android"

    def below_count(platform, threshold)
      return 0 unless AppVersion.valid?(threshold)

      @usage.fetch(platform).sum { |v, n| AppVersion.below?(v, threshold) ? n : 0 }
    end
  end
end
