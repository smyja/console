defmodule Console.AI.Evidence.Base do
  import Console.Services.Base, only: [ok: 1]
  alias Console.Deployments.Clusters
  alias Console.AI.Evidence.Component.Pod
  alias Kazan.Apis.Core.V1, as: CoreV1
  alias Kazan.Models.Apimachinery.Meta.V1, as: MetaV1

  defmacro __using__(_) do
    quote do
      import Console.AI.Evidence.Base
      import Console.Services.Base, only: [ok: 1]
      alias Kazan.Apis.Core.V1, as: CoreV1
      alias Kazan.Apis.Apps.V1, as: AppsV1
      alias Kazan.Apis.Networking.V1, as: NetworkingV1
      alias Kazan.Apis.Batch.V1, as: BatchV1
      alias Kazan.Models.Apimachinery.Meta.V1, as: MetaV1
    end
  end

  def default_empty({:ok, res}, fun), do: {:ok, fun.(res)}
  def default_empty(_, _), do: {:ok, []}

  def interpolate(str, first, last), do: "#{first}#{str}#{last}"

  def json_blob(json), do: "```json\n#{json}\n```"

  def prepend(list, l) when is_list(l), do: l ++ list
  def prepend(list, msg), do: [msg | list]

  def distro(:byok), do: "vanilla"
  def distro(distro), do: distro

  def tpl_events(%{items: [_ | _] = events}) do
    events = Enum.map(events, &event_msg/1) |> Enum.join("\n")
    [{:user, "the kubernetes events generated by this object are listed below:\n#{events}"}]
  end
  def tpl_events(_), do: []

  defp event_msg(event) do
    Map.take(event, ~w(type message reason count last_timestamp)a)
    |> Jason.encode!()
    |> json_blob()
  end

  def pod_messages(parent, pods) do
    kube = Kube.Utils.kubeconfig()
    Enum.shuffle(pods)
    |> Enum.slice(0..5)
    |> Task.async_stream(fn pod ->
      Kube.Utils.save_kubeconfig(kube)
      base = {:user, "the pod #{component(pod)} has a current state of:\n#{json_blob(encode(pod))}"}
      case Pod.hydrate(pod) do
        {:ok, msgs} -> [base | msgs]
        _ -> [base]
      end
    end)
    |> Enum.flat_map(fn {:ok, chunk} -> chunk end)
    |> prepend({:user, "the #{parent} manages a number of pods, here is a subsample of them"})
  end

  def list_pods(ns, selector) do
    &CoreV1.list_namespaced_pod!(ns, [label_selector: construct_label_selector(selector)] ++ k8s_page(&1, 500))
    |> k8s_paginator(fn p -> !ready_condition?(p.status.conditions) end, nil, [])
    |> ok()
  end

  def ready_condition?([_ | _] = conditions) do
    Enum.any?(conditions, fn
      %{type: "Ready", status: "True"} -> true
      %{"type" => "Ready", "status" => "True"} -> true
      _ -> false
    end)
  end
  def ready_condition?(_), do: false

  def k8s_page(continue, limit) when is_binary(continue), do: [continue: continue, limit: limit]
  def k8s_page(_, limit), do: [limit: limit]

  def k8s_paginator(query_fun, filter_fun, continue \\ nil, res \\ []) do
    query_fun.(continue)
    |> Kube.Utils.run()
    |> case do
      {:ok, %{metadata: %MetaV1.ListMeta{continue: c}, items: items}} when is_binary(c) and is_list(items) ->
        k8s_paginator(query_fun, filter_fun, c, res ++ Enum.filter(items, filter_fun))
      {:ok, %{items: items}} when is_list(items) ->
        res ++ Enum.filter(items, filter_fun)
      _ -> res
    end
  end

  def encode(%{__struct__: model, metadata: _} = k8s),
    do: model.encode(k8s) |> trim_managed() |> Jason.encode!()
  def encode(%{__struct__: _} = db),
    do: Console.mapify(db) |> trim_managed() |> Jason.encode!()
  def encode(%{} = map), do: Jason.encode!(trim_managed(map))

  def meaning(:stale), do: "the resource is waiting to complete provisioning"
  def meaning(:failed), do: "kubernetes has failed to provision this resource"
  def meaning(:pending), do: meaning(:stale)

  def save_kubeconfig(cluster) do
    with %Kazan.Server{} = server <- Clusters.control_plane(cluster),
      do: Kube.Utils.save_kubeconfig(server)
  end

  def items_response({:ok, %{items: items}}), do: {:ok, items}
  def items_response(err), do: err

  def component(%{group: g, version: v, kind: k, namespace: n, name: na}),
    do: "#{g}/#{v} #{k}#{ns(n)} with name #{na}"

  def component(%{api_version: api_version, kind: kind, metadata: %{name: n} = meta}) do
    "#{api_version} #{kind} namespace=#{ns(Map.get(meta, :namespace))} name=#{n}"
  end

  def component(%{"apiVersion" => api_version, "kind" => kind, "metadata" => %{"name" => n} = meta}) do
    "#{api_version} #{kind} namespace=#{ns(meta["namespace"])} name=#{n}"
  end

  def construct_label_selector(%MetaV1.LabelSelector{match_labels: labels, match_expressions: expressions}) do
    (build_labels(labels) ++ build_expressions(expressions))
    |> Enum.join(",")
  end
  def construct_label_selector(selector) when is_binary(selector), do: selector
  def construct_label_selector(%{} = labels), do: Enum.join(build_labels(labels), ",")

  def get_kind(cluster, g, v, k) do
    Console.Deployments.Clusters.api_discovery(cluster)
    |> Map.get({g, v, k})
    |> case do
      name when is_binary(name) -> name
      _ -> Kube.Utils.inflect(k)
    end
  end

  def compress_and_join(strings, joiner \\ "\n") do
    Enum.filter(strings, & &1)
    |> Enum.join(joiner)
  end

  defp build_labels(labels) when map_size(labels) > 0,
    do: Enum.map(labels, fn {k, v} -> "#{k}=#{v}" end)
  defp build_labels(_), do: []

  defp build_expressions([_ | _] = expressions) do
    Enum.map(expressions, fn
      %MetaV1.LabelSelectorRequirement{key: key, operator: op, values: [_ | _] = values} when op in ["In", "NotIn"] ->
        "#{key} #{String.downcase(op)} (#{Enum.join(values, ",")})"
      %MetaV1.LabelSelectorRequirement{key: key, operator: "Exists"} -> key
      %MetaV1.LabelSelectorRequirement{key: key} -> "!#{key}"
    end)
  end
  defp build_expressions(_), do: []

  def split_api_vsn(api_vsn) do
    case String.split(api_vsn, "/") do
      [g, v] -> {g, v}
      [v | _] -> {"core", v}
    end
  end

  def ns(ns) when is_binary(ns), do: " in namespace #{ns}"
  def ns(_), do: ""

  defp trim_managed(%{metadata: %{managed_fields: _}} = res),
    do: put_in(res.metadata.managed_fields, [])
  defp trim_managed(%{"metadata" => %{"managedFields" => _}} = res),
    do: put_in(res["metadata"]["managedFields"], [])
  defp trim_managed(res), do: res
end