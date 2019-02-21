defmodule EvercamMedia.AuthTest do
  use EvercamMedia.ModelCase

  setup do
    country = Repo.insert!(%Country{name: "Whatever", iso3166_a2: "WHTEVR"})
    user = Repo.insert!(%User{firstname: "Jake", lastname: "Doe",
      email: "jake@doe.com", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex),
      username: "jake_doe", password: "whatever123", country_id: country.id, payment_method: 0, is_admin: false, sign_in_count: 0})

    {:ok, country: country, user: user}
  end

  test "returns :valid & user if api_id and api_key are valid", context do
    assert EvercamMediaWeb.Auth.validate(context[:user].api_id, context[:user].api_key, "") == {:valid, context[:user]}
  end

  test "returns :invalid if api_id and api_key are invalid" do
    assert EvercamMediaWeb.Auth.validate("some_invalid_api_id", "some_invalid_api_key", "") == :invalid
  end

  test "returns :valid if api_id and api_key are missing" do
    assert EvercamMediaWeb.Auth.validate("", "", "") == :valid
  end
end
