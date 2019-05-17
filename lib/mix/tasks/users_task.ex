defmodule EvercamMedia.UsersTask do
  require Logger

  def update_user_keys do
    User.all
    |> Enum.each(fn(user) ->
      Logger.info "#{user.email}: API_ID: #{user.api_id}, API_KEY: #{user.api_key}"

      api_id = UUID.uuid4(:hex) |> String.slice(0..7)
      api_key = UUID.uuid4(:hex)
      user_params = %{api_id: api_id, api_key: api_key}
      User.update_user(user, user_params)
    end)
  end

end
