defprotocol Console.Deployments.PubSub.Notifiable do
  @fallback_to_any true

  @doc """
  Returns the payload and topics for a graphql subscription event
  """
  @spec message(term) :: {binary, list, map} | :ok
  def message(event)
end

defimpl Console.Deployments.PubSub.Notifiable, for: Any do
  def message(_), do: :ok
end

defmodule Console.Deployments.Notifications.Utils do
  alias Console.Schema.{Service, Cluster, Pipeline, PullRequest, StackRun, Stack}
  def filters(%Service{id: id, cluster_id: cid}), do: [service_id: id, cluster_id: cid]
  def filters(%Cluster{id: id}), do: [cluster_id: id]
  def filters(%Pipeline{id: id}), do: [pipeline_id: id]
  def filters(%PullRequest{url: url}), do: [regex: url]
  def filters(%StackRun{stack_id: id}), do: [stack_id: id]
  def filters(%Stack{id: id}), do: [stack_id: id]
  def filters(_), do: []
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.Schema.Pipeline do
  def message(_), do: :ok
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.Schema.Cluster do
  def message(_), do: :ok
end

defimpl Console.Deployments.PubSub.Notifiable, for: [
  Console.PubSub.ServiceUpdated,
] do
  alias Console.Deployments.Notifications.Utils
  def message(%{item: svc}) do
    svc = Console.Repo.preload(svc, [:cluster, :repository])
    {"service.update", Utils.filters(svc), %{service: svc, source: source(svc)}}
  end

  defp source(%{repository: %{url: url}, git: %{ref: ref, folder: folder}}), do: %{url: url, ref: "#{folder}@#{ref}"}
  defp source(%{helm: %{chart: c, version: v}}), do: %{url: c, ref: v}
  defp source(_), do: %{}
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.PullRequestCreated do
  alias Console.Deployments.Notifications.Utils

  def message(%{item: pr}) do
    {"pr.create", Utils.filters(pr), %{pr: pr}}
  end
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.PullRequestUpdated do
  alias Console.Deployments.Notifications.Utils

  def message(%{item: %{status: status} = pr}) when status in ~w(merged closed)a do
    {"pr.close", Utils.filters(pr), %{pr: pr}}
  end
  def message(_), do: :ok
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.PipelineGateUpdated do
  alias Console.Deployments.Notifications.Utils
  alias Console.Deployments.Pipelines

  def message(%{item: %{state: :pending} = gate}) do
    %{edge: %{pipeline: pipe}} = Console.Repo.preload(gate, [edge: :pipeline])
    case Pipelines.debounced?(pipe.id) do
      true -> {"pipeline.update", Utils.filters(pipe), %{pipe: pipe}}
      _ -> :ok
    end
  end
  def message(_), do: :ok
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.StackRunCreated do
  alias Console.Deployments.Notifications.Utils
  alias Console.Schema.StackRun

  def message(%{item: %StackRun{pull_request_id: id}}) when is_binary(id), do: :ok
  def message(%{item: run}) do
    run = Console.Repo.preload(run, [:stack, :repository])
    {"stack.run", Utils.filters(run), %{stack_run: run}}
  end
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.ServiceInsight do
  alias Console.Deployments.Notifications.Utils
  alias Console.Schema.AiInsight
  require Logger

  def message(%{item: {svc, %AiInsight{text: t} = insight}}) when byte_size(t) > 0 do
    Timex.now()
    |> Timex.shift(minutes: -5)
    |> Timex.before?(ts(insight))
    |> case do
      true ->
        svc = Console.Repo.preload(svc, [:cluster, :repository])
        {"service.insight", Utils.filters(svc), %{service: svc, insight: insight}}
      _ -> :ok
    end
  end
  def message(_), do: :ok

  defp ts(%AiInsight{inserted_at: iat, updated_at: uat}), do: uat || iat
end

defimpl Console.Deployments.PubSub.Notifiable, for: Console.PubSub.StackInsight do
  alias Console.Deployments.Notifications.Utils
  alias Console.Schema.AiInsight
  require Logger

  def message(%{item: {stack, %AiInsight{text: t} = insight}}) when byte_size(t) > 0 do
    Timex.now()
    |> Timex.shift(minutes: -5)
    |> Timex.before?(ts(insight))
    |> case do
      true ->
        stack = Console.Repo.preload(stack, [:cluster, :repository])
        {"stack.insight", Utils.filters(stack), %{stack: stack, insight: insight}}
      _ -> :ok
    end
  end
  def message(_), do: :ok

  defp ts(%AiInsight{inserted_at: iat, updated_at: uat}), do: uat || iat
end
