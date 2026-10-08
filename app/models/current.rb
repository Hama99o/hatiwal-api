# Request-scoped facts the serializers need without threading options through
# every controller (privacy-b, 2026-10-08). Reset by Rails after each request;
# outside a request (jobs, cable broadcasts) everything is nil / empty, which
# means the strictest output: no owner id.
class Current < ActiveSupport::CurrentAttributes
  # A client older than 1.1.6 (or one that sends no version): it predates
  # shops and expects a person's id where a shop's face is shown.
  attribute :legacy_shop_ids
  # A proc returning the viewer, called only when a shop's face is serialized:
  # endpoints that never show one (e.g. app_config) do no per-user work.
  attribute :viewer_resolver

  # Memo of viewer_shop_ids. An ATTRIBUTE, not an instance variable: Rails
  # clears attributes between requests, so one viewer's shops can never leak
  # into the next request served by the same thread.
  attribute :viewer_shop_ids_memo

  # The shops the viewer is on (owner, manager or staff), once per request.
  def viewer_shop_ids
    self.viewer_shop_ids_memo ||= begin
      viewer = viewer_resolver&.call
      viewer ? viewer.shop_members.pluck(:shop_id).to_set : Set.new
    end
  end
end
