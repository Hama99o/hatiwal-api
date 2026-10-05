# UPD-1 — the app config is public (every app checks it before signing in);
# the settings themselves are edited only through the admin session.
class AppReleaseSettingPolicy < ApplicationPolicy
  def show? = true
end
