defmodule EvercamMedia.HTTPClient do
  alias EvercamMedia.HTTPClient.DigestAuth
  require Logger

  def get(url) do
    hackney = [pool: :snapshot_pool]
    HTTPoison.get url, [], hackney: hackney
  end

  def get(:digest_auth, response, url, username, password) do
    digest_token = DigestAuth.get_digest_token(response, url, username, password)
    hackney = [pool: :snapshot_pool]
    HTTPoison.get url, ["Authorization": "Digest #{digest_token}"], hackney: hackney
  end

  def get(:basic_auth, url, "", "") do
    get(url)
  end

  def get(:basic_auth, url, username, password) do
    hackney = [basic_auth: {username, password}, pool: :snapshot_pool]
    HTTPoison.get url, [], hackney: hackney
  end

  def get(:basic_android_auth, url, username, password) do
    hackney = [basic_auth: {username, password}, timeout: 15_000]
    HTTPoison.get url, [], hackney: hackney
  end

  def get(:digest_auth, url, username, password) do
    case get(url) do
      {:ok, response} ->
        chooose_auth(response, url, username, password)
      response ->
        response
    end
  end

  def get(:cookie_auth, snapshot_url, username, password) do
    u = URI.parse(snapshot_url)
    login_url = u.scheme <> "://" <> u.authority <> "/login.cgi"
    cookie = get_cookie(login_url, username, password)
    hackney = [pool: :snapshot_pool]
    headers = ["Cookie": cookie]
    HTTPoison.get snapshot_url, headers, hackney: hackney
  end

  def put(url, username, password, body) do
    res =
      case get(url) do
        {:ok, response} -> response
        response -> response
      end
    auth = get_auth(res, url, username, password, "PUT")
    HTTPoison.put(url, body, ["Content-Type": "application/x-www-form-urlencoded", "Authorization": "#{auth}"])
  end

  defp get_auth(response, url, username, password, method) do
    case response.headers |> Enum.find(fn({k, v}) -> k == "WWW-Authenticate" && String.starts_with?(v, "Digest")  end) do
      nil -> "Basic #{Base.encode64("#{username}:#{password}")}"
      _ -> "Digest #{DigestAuth.get_digest_token(response, url, username, password, method)}"
    end
  end

  defp get_cookie(url, username, password) do
    case get(url) do
      {:ok, response} ->
        cookie = parse_cookie_header(response)
        if cookie == nil do
          Logger.error "Cookie is not set for url: #{url}"
          raise "Cookie is not set for url: #{url}"
        end
        hackney = [pool: :snapshot_pool]
        headers = ["Content-Type": "multipart/form-data; boundary=----WebKitFormBoundaryEq1VsbBovj79sSoL", "Cookie": cookie]
        HTTPoison.post(url, multipart_text(username, password), headers, hackney: hackney)
        cookie
      response ->
        response
    end
  end

  defp chooose_auth(response, url, username, password) do
    case response.headers |> Enum.find(fn({k, v}) -> k == "WWW-Authenticate" && String.starts_with?(v, "Digest")  end) do
      nil -> get(:basic_auth, url, username, password)
      _ -> get(:digest_auth, response, url, username, password)
    end
  end

  defp parse_cookie_header(response) do
    case response.headers |> Enum.find(fn({k, _v}) -> k == "Set-Cookie" end) do
      {"Set-Cookie", cookie_string} ->
        case Regex.run(~r/(AIROS_SESSIONID=[a-z0-9]+)/, cookie_string) do
          [h|_] -> h
          _ -> nil
        end
      _ -> nil
    end
  end

  defp multipart_text(username, password) do
    "------WebKitFormBoundaryEq1VsbBovj79sSoL\r\nContent-Disposition: form-data;name=\"uri\"\r\n\r\n\r\n------WebKitFormBoundaryEq1VsbBovj79sSoL\r\nContent-Disposition:form-data; name=\"username\"\r\n\r\n#{username}\r\n------WebKitFormBoundaryEq1VsbBovj79sSoL\r\nContent-Disposition: form-data; name=\"password\"\r\n\r\n#{password}\r\n------WebKitFormBoundaryEq1VsbBovj79sSoL\r\nContent-Disposition: form-data; name=\"Submit\"\r\n\r\nLogin\r\n------WebKitFormBoundaryEq1VsbBovj79sSoL\r\n"
  end
end

defmodule EvercamMedia.HTTPClient.DigestAuth do
  def get_digest_token(response, url, username, password, method \\ "GET") do
    case response.headers |> Enum.find(fn({k, v}) -> k == "WWW-Authenticate" && String.starts_with?(v, "Digest") end) do
      {"WWW-Authenticate", auth_string} ->
        digest_head = parse_digest_header(auth_string)
        %{"realm" => realm, "nonce" => nonce} = digest_head
        cnonce = :crypto.strong_rand_bytes(16) |> md5
        url = URI.parse(url)
        response = create_digest_response(
          method,
          username,
          password,
          realm,
          digest_head |> Map.get("qop"),
          url.path,
          nonce,
          cnonce
        )
        [{"username", username},
         {"realm", realm},
         {"nonce", nonce},
         {"uri", url.path},
         {"cnonce", cnonce},
         {"response", response}]
        |> add_opaque(digest_head |> Map.get("opaque"))
        |> Enum.map(fn {key, val} -> {key, "\"#{val}\""} end)
        |> add_nonce_counter
        |> add_auth(digest_head |> Map.get("qop"))
        |> Enum.map(fn {key, val} -> "#{key}=#{val}" end)
        |> Enum.join(", ")
      _ ->
        raise "No string found"
    end
  end

  defp parse_digest_header(auth_head) do
    case Regex.scan(~r/(\w+\s*)=\"([\w=\s|()|:+\/\\]+)/, auth_head) do
      [] ->
        raise "Error in digest authentication header: #{auth_head}"
      parsed ->
        parsed
        |> Enum.map(fn([_, key, val]) -> {key, val} end)
        |> Enum.into(%{})
    end
  end

  defp create_digest_response(method, username, password, realm, qop, uri, nonce, cnonce) do
    ha1 = [username, realm, password] |> Enum.join(":") |> md5
    ha2 = ["#{method}", uri] |> Enum.join(":") |> md5
    do_create_digest_response(ha1, ha2, qop, nonce, cnonce)
  end

  defp do_create_digest_response(ha1, ha2, nil, nonce, _cnonce) do
    [ha1, nonce, ha2] |> Enum.join(":") |> md5
  end
  defp do_create_digest_response(ha1, ha2, _qop, nonce, cnonce) do
    [ha1, nonce, "00000001", cnonce, "auth", ha2] |> Enum.join(":") |> md5
  end

  defp add_opaque(digest, nil), do: digest
  defp add_opaque(digest, opaque), do: [{"opaque", opaque} | digest]

  defp add_nonce_counter(digest), do: [{"nc", "00000001"} | digest]

  defp add_auth(digest, nil), do: digest
  defp add_auth(digest, cop) do
    case String.contains?(cop, "auth") do
      true -> [{"qop", "\"auth\""} | digest]
      false -> digest
    end
  end

  defp md5(data) do
    Base.encode16(:erlang.md5(data), case: :lower)
  end
end
