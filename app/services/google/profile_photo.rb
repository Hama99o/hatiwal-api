# Fetches a Google profile photo (the `picture` of a Google ID token) to become a
# NEW account's avatar (GoogleAvatarImportJob, owner 2026-10-29).
#
# The URL comes from the token payload, so it is fetched as UNTRUSTED input (SSRF):
#   - https on port 443 only, no user info, a host under googleusercontent.com;
#   - NO redirect followed (Faraday follows none without the middleware; a 3xx is refused);
#   - 5 s to connect and 5 s to read;
#   - at most MAX_BYTES, counted while streaming (and a larger Content-Length refused);
#   - an image Content-Type, and image bytes (Marcel), from the avatar's own list.
# A refusal raises Refused (never retried); network errors raise Faraday::Error (the job
# retries those once).
module Google
  module ProfilePhoto
    HOST_SUFFIX = ".googleusercontent.com".freeze
    # Google serves 96 px by default; the trailing "=s96-c" option sets the size.
    SIZE_OPTION = "=s400-c".freeze
    MAX_BYTES = User::MAX_AVATAR_SIZE
    TIMEOUT = 5
    IMAGE_TYPES = AttachedFileValidator::IMAGE_TYPES

    class Refused < StandardError; end

    Photo = Struct.new(:io, :content_type)

    module_function

    def fetch(raw_url)
      uri = sized_uri(raw_url)
      bytes = +""
      response = connection.get(uri.to_s) do |req|
        req.options.on_data = proc do |chunk, _received|
          bytes << chunk
          raise Refused, "over #{MAX_BYTES} bytes" if bytes.bytesize > MAX_BYTES
        end
      end
      check_response!(response, bytes)
      Photo.new(StringIO.new(bytes), image_type!(bytes))
    end

    # The URL to fetch, asking for 400 px; Refused unless it is a Google photo host.
    def sized_uri(raw_url)
      uri = URI.parse(raw_url.to_s)
      unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && google_host?(uri.host)
        raise Refused, "not a Google photo URL"
      end

      uri.path = uri.path.sub(/=[^\/=]*\z/, "") + SIZE_OPTION
      uri
    rescue URI::InvalidURIError
      raise Refused, "not a URL"
    end

    def google_host?(host)
      host.present? && host.downcase.end_with?(HOST_SUFFIX)
    end

    def connection
      Faraday.new(request: { open_timeout: TIMEOUT, read_timeout: TIMEOUT, timeout: TIMEOUT })
    end

    def check_response!(response, bytes)
      raise Refused, "HTTP #{response.status}" unless response.status == 200
      raise Refused, "declared over #{MAX_BYTES} bytes" if response.headers["content-length"].to_i > MAX_BYTES
      raise Refused, "empty" if bytes.empty?

      declared = response.headers["content-type"].to_s.split(";").first.to_s.strip.downcase
      raise Refused, "declared #{declared.presence || 'no type'}" unless IMAGE_TYPES.include?(declared)
    end

    # The type the BYTES say (the header is only a claim).
    def image_type!(bytes)
      type = Marcel::MimeType.for(StringIO.new(bytes))
      raise Refused, "the bytes are #{type}" unless IMAGE_TYPES.include?(type)

      type
    end
  end
end
