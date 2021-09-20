defmodule Console.Services.Runbooks do
  alias Kube.{Runbook, Client}
  alias Console.Schema.User
  alias Console.Runbooks

  @type error :: {:error, term}

  @spec runbook(binary, binary) :: {:ok, Runbook.t} | error
  def runbook(namespace, name) do
    Client.get_runbook(namespace, name)
  end

  @spec list_runbooks(binary) :: {:ok, [Runbook.t]} | error
  def list_runbooks(namespace) do
    with {:ok, %{items: items}} <- Client.list_runbooks(namespace),
      do: {:ok, items}
  end

  @spec datasources(Runbook.t) :: {:ok, [map]} | error
  def datasources(%Runbook{spec: %{datasources: sources}} = book) do
    Task.async_stream(sources, &Runbooks.Data.extract(&1, book))
    |> Console.stream_result()
  end

  @spec execute(Runbook.t, binary, binary, map, User.t) :: {:ok | :error, term}
  def execute(%Runbook{spec: %{actions: actions}}, action, repo, ctx, %User{} = user) do
    actor = Runbooks.Actor.build(repo, ctx, user)
    with %Runbook.Action{} = act <- Enum.find(actions, & &1.name == action),
      do: Runbooks.Actor.enact(act, actor)
  end
end
