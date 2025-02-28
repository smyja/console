defmodule Console.AI.Evidence.Vector do
  alias Console.AI.{
    Provider,
    VectorStore,
    Tools.Vector,
    Evidence.Context
  }

  require Logger

  @preface """
  The following is a description of the evidence for troubleshooting a kubernetes related issue.  Determine whether
  we should search an external vector store for additional context, containing information like historical PRs and
  alert information (including postmortems). This is normally not needed for base yaml misconfigurations, but
  can be needed for things like crash loops, OOM errors or other errors that can only be caused by software running in a
  container.
  """

  @spec with_vector_data(Provider.history | Context.t) :: Context.t
  def with_vector_data(history) do
    ctx = Context.new(history)
    with true <- VectorStore.enabled?(),
         {:ok, %Vector{query: query}} <- use_vector(ctx.history),
         {:ok, [_ | _] = vdata} <- VectorStore.fetch(query) do
      Context.prompt(ctx, {:user, "I've also found some relevent external data that could add additional context to what caused the issue:"})
      |> Context.reduce(vdata, &Context.prompt(&2, {:user, vector_prompt(&1)}))
      |> Context.evidence(vector_evidence(vdata))
    else
      _ ->
        Logger.debug "skipping vector store extraction"
        Context.new(history)
    end
  end

  defp vector_prompt(%VectorStore.Response{alert_resolution: alert_resolution}),
    do: "A prior alert resolution with data like so: #{json!(alert_resolution)}"
  defp vector_prompt(%VectorStore.Response{pr_file: pr_file}), do: "A file from a given pr with data like so: #{json!(pr_file)}"

  defp vector_evidence(vdata) do
    Enum.map(vdata, fn
      %VectorStore.Response{pr_file: pr_file} -> %{pull_request: Map.from_struct(pr_file), type: :pr}
      %VectorStore.Response{alert_resolution: res}  -> %{alert_resolution: Map.from_struct(res), type: :alert}
      _ -> nil
    end)
    |> Enum.filter(& &1)
  end

  defp use_vector(history) do
    case Provider.tool_call(history, [Vector], preface: @preface) do
      {:ok, [%{vector: %{result: %Vector{required: true} = vector}} | _]} ->
        {:ok, vector}
      _ -> false
    end
  end

  defp json!(%{__struct: _} = args), do: Map.from_struct(args) |> json!()
  defp json!(data), do: Jason.encode!(data)
end
