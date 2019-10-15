defmodule ElixirDropbox.Client do
  defstruct access_token: nil

  @type access_token :: %{access_token: binary}
  @type t :: %__MODULE__{access_token: access_token}

  @spec new() :: t
  def new(), do: %__MODULE__{}

  @spec new(access_token) :: t
  def new(access_token) do
    %__MODULE__{access_token: access_token}
  end
end

defmodule ElixirDropbox.Files.UploadSession do
  def start(client, close, file) do
    dropbox_headers = %{
      :close => close
    }

    headers = %{
      "Dropbox-API-Arg" => Jason.encode!(dropbox_headers),
      "Content-Type" => "application/octet-stream"
    }

    ElixirDropbox.upload_request(
      client,
      Application.get_env(:evercam_media, :upload_url),
      "files/upload_session/start",
      file,
      headers
    )
  end

  def finish_batch(client, entries) do
    body = %{"entries" => entries}
    result = to_string(Jason.Encoder.encode(body, []))
    ElixirDropbox.post(client, "/files/upload_session/finish_batch", result)
  end
end

defmodule ElixirDropbox do
  use HTTPoison.Base

  @base_url Application.get_env(:evercam_media, :base_url)

  def post(client, url, body \\ "") do
    headers = json_headers()
    post_request(client, "#{@base_url}#{url}", body, headers)
  end

  def post_url(client, base_url, url, body \\ "") do
    headers = json_headers()
    post_request(client, "#{base_url}#{url}", body, headers)
  end

  def process_response(%HTTPoison.Response{status_code: 200, body: body}), do: Jason.decode!(body)

  def process_response(%HTTPoison.Response{status_code: status_code, body: body}) do
    cond do
      status_code in 400..599 ->
        {{:status_code, status_code}, Jason.decode(body)}
    end
  end

  def download_response(%HTTPoison.Response{status_code: 200, body: body, headers: headers}),
    do: %{body: body, headers: headers}

  def download_response(%HTTPoison.Response{status_code: status_code, body: body}) do
    cond do
      status_code in 400..599 ->
        {{:status_code, status_code}, Jason.decode(body)}
    end
  end

  def post_request(client, url, body, headers) do
    headers = Map.merge(headers, headers(client))
    HTTPoison.post!(url, body, headers) |> process_response
  end

  def upload_request(client, base_url, url, data, headers) do
    post_request(client, "#{base_url}#{url}", {:file, data}, headers)
  end

  def download_request(client, base_url, url, data, headers) do
    headers = Map.merge(headers, headers(client))
    HTTPoison.post!("#{base_url}#{url}", data, headers) |> download_response
  end

  def headers(client) do
    %{"Authorization" => "Bearer #{client.access_token}"}
  end

  def json_headers do
    %{"Content-Type" => "application/json"}
  end
end
