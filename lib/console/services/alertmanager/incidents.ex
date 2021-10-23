defmodule Console.Alertmanager.Incidents do
  use Console.Services.Base
  use Nebulex.Caching
  alias Console.Schema.AlertmanagerIncident
  alias Console.Plural.{Incident, Incidents}
  alias Alertmanager.Alert

  @behaviour Console.Alertmanager.Sink

  @ttl Nebulex.Time.expiry_time(6, :hour)

  def name(), do: :incident

  def handle_alert(%Alert{labels: %{"namespace" => ns, "severity" => "critical"}, fingerprint: fp} = alert) do
    repo = Console.from_namespace(ns)

    case Console.Services.Alertmanager.get_mapping(fp) do
      %{incident_id: id} = mapping ->
        with :not_found <- update_incident(id, alert),
             {:ok, _} <- Console.Repo.delete(mapping),
          do: create_incident(repo, alert)
      _ -> create_incident(repo, alert)
    end
  end
  def handle_alert(_), do: :ok

  @resolved ~w(RESOLVED COMPLETE)
  @active ~w(OPEN IN_PROGRESS)

  defp update_incident(id, alert) do
    case {alert, Incidents.get_incident(id)} do
      {%Alert{status: :firing}, {:ok, %Incident{status: status}}} when status in @resolved ->
        Incidents.update_incident(id, Map.merge(base_attributes(alert), %{status: "IN_PROGRESS"}))
      {%Alert{status: :resolved}, {:ok, %Incident{status: status}}} when status in @active ->
        Incidents.update_incident(id, %{status: "RESOLVED"})
      {%Alert{status: :firing}, _} ->
        Incidents.update_incident(id, base_attributes(alert))
      {_, {:error, _}} -> :not_found
      _ -> :ok
    end
  end

  defp create_incident(repo, %Alert{status: :firing} = alert) do
    Incidents.create_incident(repo, Map.merge(base_attributes(alert), %{
      severity: 1,
      tags: [%{tag: "alertmanager"}, %{tag: "console"}],
      cluster_information: cluster_info()
    }))
    |> when_ok(fn %{id: incident_id} ->
      %AlertmanagerIncident{}
      |> AlertmanagerIncident.changeset(%{
        incident_id: incident_id,
        fingerprint: alert.fingerprint
      })
      |> Console.Repo.insert()
    end)
  end
  defp create_incident(_, _), do: :ok

  defp base_attributes(alert) do
    %{
      title: alert.summary,
      description: description(alert.description)
    }
  end

  def description(desc) do
    """
    #{desc}

    **This incident was autogenerated by the plural console's alertmanager webhook**
    """
  end

  @decorate cacheable(cache: Console.Cache, key: :cluster_info, opts: [ttl: @ttl], match: &cacheable?/1)
  def cluster_info() do
    Kazan.Apis.Version.get_code!()
    |> Kazan.run()
    |> when_ok(&build_cluster_info/1)
    |> case do
      {:ok, info} -> info
      _ -> nil
    end
  end

  defp build_cluster_info(%{version: %{major: maj, minor: min}} = info) do
    Map.take(info, [:git_commit, :platform])
    |> Map.put(:version, "#{maj}.#{min}")
  end
  defp build_cluster_info(info), do: Map.take(info, [:git_commit, :platform, :version])

  defp cacheable?(nil), do: false
  defp cacheable?(_), do: true
end
