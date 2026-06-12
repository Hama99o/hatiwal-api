# frozen_string_literal: true

require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Hatiwal API v1",
        version: "v1",
        description: "Local marketplace API for Afghanistan — no online payment, meetup-based transactions"
      },
      paths: {},
      servers: [
        {
          url: "https://{defaultHost}",
          variables: {
            defaultHost: { default: "api.hatiwal.com" }
          }
        },
        {
          url: "http://localhost:3007",
          description: "Local development"
        }
      ],
      components: {
        securitySchemes: {
          bearer: {
            type: :apiKey,
            name: "access-token",
            in: :header
          }
        }
      }
    }
  }

  config.openapi_format = :yaml
end
