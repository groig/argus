defmodule Argus.Ingest.Scrubber do
  @moduledoc false

  @filtered "[Filtered]"

  @sensitive_keys MapSet.new(~w(
    password
    passwd
    passphrase
    password_confirmation
    secret
    secret_key
    client_secret
    api_key
    apikey
    x_api_key
    auth
    authorization
    proxy_authorization
    credentials
    credential
    mysql_pwd
    privatekey
    private_key
    token
    access_token
    refresh_token
    id_token
    session
    sessionid
    session_id
    cookie
    set_cookie
    csrftoken
    csrf_token
    x_csrftoken
  ))

  @sensitive_prefixes ~w(
    password_
    passwd_
    passphrase_
    secret_
    token_
    credential_
    credentials_
  )

  @sensitive_suffixes ~w(
    _password
    _passwd
    _passphrase
    _secret
    _token
    _api_key
    _private_key
    _auth
    _authorization
    _credential
    _credentials
    _cookie
  )

  @url_userinfo_regex ~r{([a-z][a-z0-9+.-]*://[^:/\s@]+:)([^@\s/]+)(@)}i
  @query_parameter_regex ~r{([?&])([^=&\s]+)=([^&#\s]*)}

  def scrub(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, nested_value} ->
      if sensitive_key?(key) do
        {key, @filtered}
      else
        {key, scrub(nested_value)}
      end
    end)
  end

  def scrub(value) when is_list(value), do: Enum.map(value, &scrub/1)

  def scrub(value) when is_binary(value) do
    value
    |> scrub_url_userinfo()
    |> scrub_query_parameters()
  end

  def scrub(value), do: value

  defp sensitive_key?(key) when is_binary(key) or is_atom(key) do
    normalized_key = normalize_key(key)

    MapSet.member?(@sensitive_keys, normalized_key) or
      Enum.any?(@sensitive_prefixes, &String.starts_with?(normalized_key, &1)) or
      Enum.any?(@sensitive_suffixes, &String.ends_with?(normalized_key, &1))
  end

  defp sensitive_key?(_key), do: false

  defp normalize_key(key) do
    key
    |> to_string()
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp scrub_url_userinfo(value) do
    Regex.replace(@url_userinfo_regex, value, "\\1#{@filtered}\\3")
  end

  defp scrub_query_parameters(value) do
    Regex.replace(
      @query_parameter_regex,
      value,
      fn full_match, separator, key, _value ->
        if sensitive_key?(decode_query_key(key)) do
          separator <> key <> "=" <> @filtered
        else
          full_match
        end
      end
    )
  end

  defp decode_query_key(key) do
    URI.decode_www_form(key)
  rescue
    ArgumentError -> key
  end
end
