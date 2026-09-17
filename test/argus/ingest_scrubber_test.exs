defmodule Argus.Ingest.ScrubberTest do
  use ExUnit.Case, async: true

  alias Argus.Ingest.Scrubber

  test "recursively filters credential fields without removing their keys" do
    payload = %{
      "conn_params" => %{
        "host" => "db.example.com",
        "password" => "database-secret"
      },
      "frames" => [
        %{
          "vars" => %{
            "apiKey" => "api-secret",
            "request.auth" => "auth-secret",
            "password_confirmation" => "confirmation-secret"
          }
        }
      ],
      "user" => %{
        "email" => "person@example.com",
        "ip_address" => "192.0.2.1",
        "session_duration" => 60
      }
    }

    scrubbed = Scrubber.scrub(payload)

    assert get_in(scrubbed, ["conn_params", "password"]) == "[Filtered]"
    assert get_in(scrubbed, ["frames", Access.at(0), "vars", "apiKey"]) == "[Filtered]"

    assert get_in(scrubbed, ["frames", Access.at(0), "vars", "request.auth"]) ==
             "[Filtered]"

    assert get_in(scrubbed, ["frames", Access.at(0), "vars", "password_confirmation"]) ==
             "[Filtered]"

    assert get_in(scrubbed, ["conn_params", "host"]) == "db.example.com"
    assert scrubbed["user"] == payload["user"]
  end

  test "filters URL passwords and sensitive query parameters inside strings" do
    payload = %{
      "database_url" => "postgresql://worker:database-secret@db.example.com/app?sslmode=require",
      "request_url" => "https://example.com/callback?access_token=query-secret&view=full#details",
      "safe_url" => "https://example.com/search?email=person%40example.com"
    }

    assert Scrubber.scrub(payload) == %{
             "database_url" =>
               "postgresql://worker:[Filtered]@db.example.com/app?sslmode=require",
             "request_url" =>
               "https://example.com/callback?access_token=[Filtered]&view=full#details",
             "safe_url" => "https://example.com/search?email=person%40example.com"
           }
  end

  test "is idempotent and preserves ordinary scalar values" do
    payload = %{
      "password" => "database-secret",
      "count" => 3,
      "active" => true,
      "missing" => nil
    }

    scrubbed = Scrubber.scrub(payload)

    assert Scrubber.scrub(scrubbed) == scrubbed

    assert Map.take(scrubbed, ["count", "active", "missing"]) ==
             Map.take(payload, ["count", "active", "missing"])
  end
end
