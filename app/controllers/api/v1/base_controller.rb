class Api::V1::BaseController < ApplicationController
  before_action :authenticate_user!
  # Runs after authentication so current_user is resolved: a user blocked while
  # holding a valid token is rejected with a clear message on every request.
  before_action :reject_blocked_user!
end
