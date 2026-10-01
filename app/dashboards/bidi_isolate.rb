# Wraps a user-typed name (a listing title, a person's name) in Unicode
# first-strong isolate marks (U+2068 … U+2069) before Administrate puts it
# inside an English line — "Show …", the "Edit …" button, the tab <title>,
# select options. Without it a Pashto/Dari/Urdu title fragments around any
# Latin character in it ("۳x۴") and drags the surrounding English with it.
# The marks are invisible and plain text, so they are safe everywhere,
# including <title> where HTML (<bdi>) is not.
module BidiIsolate
  FSI = "⁨".freeze
  PDI = "⁩".freeze

  def self.wrap(text)
    "#{FSI}#{text}#{PDI}"
  end
end
