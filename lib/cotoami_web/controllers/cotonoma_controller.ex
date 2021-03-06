defmodule CotoamiWeb.CotonomaController do
  use CotoamiWeb, :controller
  require Logger
  alias Cotoami.{Cotonoma, CotoService, CotonomaService}
  alias CotoamiWeb.CotoView

  plug(:scrub_params, "cotonoma" when action in [:create])

  def action(conn, _) do
    apply(__MODULE__, action_name(conn), [conn, conn.params, conn.assigns.amishi])
  end

  def index(conn, _params, amishi) do
    render(conn, "index.json", %{
      global: CotonomaService.global_cotonomas(),
      recent: CotonomaService.recent_cotonomas(amishi)
    })
  end

  def sub(conn, %{"cotonoma_id" => cotonoma_id}, _amishi) do
    render(conn, "cotonomas.json", %{
      cotonomas: CotonomaService.sub_cotonomas(cotonoma_id)
    })
  end

  def create(
        conn,
        %{
          "cotonoma" => %{
            "cotonoma_id" => cotonoma_id,
            "name" => name,
            "shared" => shared
          }
        },
        amishi
      ) do
    coto = CotonomaService.create!(amishi, name, shared, cotonoma_id)

    if coto.posted_in do
      broadcast_post(coto, coto.posted_in.key, amishi, conn.assigns.client_id)
      broadcast_cotonoma_update(coto.posted_in, amishi, conn.assigns.client_id)
    end

    render(conn, CotoView, "created.json", coto: coto)
  rescue
    e in Ecto.ConstraintError ->
      send_resp_by_constraint_error(conn, e)
  end

  @cotos_options ["exclude_pinned_graph"]

  def cotos(conn, %{"key" => key, "page" => page} = params, amishi) do
    page_index = String.to_integer(page)

    options =
      Enum.map(@cotos_options, fn key ->
        {String.to_atom(key), Map.has_key?(params, key)}
      end)

    case CotoService.get_cotos_by_cotonoma(key, amishi, page_index, options) do
      nil ->
        send_resp(conn, :not_found, "")

      paginated_results ->
        render(conn, "cotos.json", paginated_results)
    end
  rescue
    _ in Cotoami.Exceptions.NoPermission ->
      send_resp(conn, :not_found, "")
  end

  def stats(conn, %{"key" => key}, _amishi) do
    stats =
      Cotonoma
      |> Repo.get_by!(key: key)
      |> CotonomaService.stats()

    json(conn, stats)
  end
end
