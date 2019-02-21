defmodule EvercamMedia.ONVIFControllerEventsTest do
  use EvercamMediaWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]

  @auth System.get_env["ONVIF_AUTH"]

  @moduletag :onvif
  @access_params "url=http://recorded_response&auth=#{@auth}"

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  test "GET /v2/onvif/v20/Events/GetServiceCapabilities, returns something", context do
    use_cassette "ev_get_service_capabilities" do
      conn = get build_conn(), "/v2/onvif/v20/Events/GetServiceCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      subscription_policy_support = json_response(conn, 200) |> Map.get("Capabilities") |> Map.get("WSSubscriptionPolicySupport")
      assert subscription_policy_support == "true"
    end
  end

  test "GET /v2/onvif/v20/Events/GetEventProperties, returns something", context do
    use_cassette "get_event_properties" do
      conn = get build_conn(), "/v2/onvif/v20/Events/GetEventProperties?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      fixed_topic_set = json_response(conn, 200) |> Map.get("FixedTopicSet")
      assert fixed_topic_set == "true"
    end
  end
end
