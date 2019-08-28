defmodule EvercamMediaWeb.Auth do
  alias EvercamMediaWeb.JwtAuthToken

  def validate("", "", ""), do: :valid
  def validate(api_id, api_key, token) do
    cond do
      user = User.get_by_api_keys(api_id, api_key) -> {:valid, user}
      user = jwt_auth(token) -> {:valid, user}
      token = User.get_user_from_token(token) -> {:valid, token}
      true -> :invalid
    end
  end

  defp jwt_auth(token) do
    token
    |> AccessToken.by_request_token
    |> handle_response(token)
  end

  defp handle_response(nil, _), do: nil
  defp handle_response({:ok, claims}, _), do: User.by_username_or_email(claims["user_id"])
  defp handle_response({:error, _}, _), do: nil
  defp handle_response(_, token), do: JwtAuthToken.verify_and_validate(token) |> handle_response(token)
end
