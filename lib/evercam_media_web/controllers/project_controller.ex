defmodule EvercamMediaWeb.ProjectController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger

  def index(conn, _params) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller)
    do
      projects = Project.by_user(caller.id)
      render(conn, "index.json", %{projects: projects})
    end
  end

  def show(conn, %{"id" => project_exid}) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller),
         {:ok, project} <- project_exist(conn, project_exid)
    do
      render(conn, "show.json", %{project: project})
    end
  end

  def create(conn, %{"name" => project_name}) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller)
    do
      project_changeset = Project.changeset(%Project{}, %{user_id: caller.id, name: project_name})
      case Repo.insert(project_changeset) do
        {:ok, project} ->
          complete_project =
            project
            |> Repo.preload(:cameras, force: true)
            |> Repo.preload(:user, force: true)
            |> Repo.preload(:overlays, force: true)
          conn
          |> put_status(:created)
          |> render("show.json", %{project: complete_project})
        {:error, changeset} -> render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def add_overlay(conn, %{"id" => project_exid, "sw_lat" => sw_lat, "sw_lng" => sw_lng, "ne_lat" => ne_lat, "ne_lng" => ne_lng } = params) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller),
         {:ok, project} <- project_exist(conn, project_exid)
    do
      sw_points = %Geo.Point{coordinates: {sw_lng, sw_lat}}
      ne_points = %Geo.Point{coordinates: {ne_lng, ne_lat}}
      EvercamMedia.Snapshot.Storage.save_map_file(params["image_name"], params["file_url"], params["file_extension"], params["fileType"])
      path = "https://s3-eu-west-1.amazonaws.com/evercam-camera-assets/mapping/#{params["image_name"]}.#{params["file_extension"]}"
      case Overlay.insert_overlay(project.id, path, sw_points, ne_points) do
        {:ok, overlay} ->
          conn
          |> json(%{id: overlay.id, path: overlay.path, sw_bounds: Overlay.get_location(overlay.sw_bounds), ne_bounds: Overlay.get_location(overlay.ne_bounds)})
        {:error, changeset} -> render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def update_overlay(conn, %{"id" => project_exid, "overlay_id" => overlay_id, "sw_lat" => sw_lat, "sw_lng" => sw_lng, "ne_lat" => ne_lat, "ne_lng" => ne_lng }) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller),
         {:ok, _project} <- project_exist(conn, project_exid),
         {:ok, overlay} <- overlay_exist(conn, overlay_id)
    do
      sw_points = %Geo.Point{coordinates: {sw_lng, sw_lat}}
      ne_points = %Geo.Point{coordinates: {ne_lng, ne_lat}}
      overlay_changeset = Overlay.changeset(overlay, %{sw_bounds: sw_points, ne_bounds: ne_points})

      case Evercam.Repo.update(overlay_changeset) do
        {:ok, overlay} ->
          conn
          |> json(%{id: overlay.id, path: overlay.path, sw_bounds: Overlay.get_location(overlay.sw_bounds), ne_bounds: Overlay.get_location(overlay.ne_bounds)})
        {:error, changeset} -> render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def delete_overlay(conn, %{"id" => project_exid, "overlay_id" => overlay_id}) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller),
         {:ok, _project} <- project_exist(conn, project_exid),
         {:ok, overlay} <- overlay_exist(conn, overlay_id)
    do
      Overlay.delete_by_id(overlay.id)
      spawn(fn ->
        ["mapping/#{overlay.path |> String.split("/") |> List.last}"]
        |> EvercamMedia.TimelapseRecording.S3.delete_object
      end)
      json(conn, %{})
    end
  end

  defp project_exist(conn, project_exid) do
    case Project.by_exid(project_exid) do
      nil -> render_error(conn, 404, "Project not found.")
      %Project{} = project -> {:ok, project}
    end
  end

  defp overlay_exist(conn, overlay_id) do
    case Overlay.by_id(overlay_id) do
      nil -> render_error(conn, 404, "Overlay not found.")
      %Overlay{} = overlay -> {:ok, overlay}
    end
  end
end
