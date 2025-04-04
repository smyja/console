defmodule Console.Watchers.Upgrade do
  use Console.Watchers.Base, state: [:upgrades, :queue_id, :target, :last]
  # import Console.Services.Base, only: [
  #   start_transaction: 0,
  #   add_operation: 3,
  #   execute: 1
  # ]
  alias Console.Clustering.Info
  alias Console.Deployments.Services
  alias Console.Plural.{Upgrades, Socket}
  alias Console.Watchers.Plural

  @poll_interval 60 * 1000
  @resource_interval :timer.minutes(60)

  def record_usage() do
    with pid when is_pid(pid) <- Process.whereis(__MODULE__),
         true <- Process.alive?(pid),
      do: GenServer.call(__MODULE__, :usage)
  end

  def handle_call(:state, _, state), do: {:reply, state, state}
  def handle_call(:ping, _, state), do: {:reply, :pong, state}

  def handle_call(:usage, _, state) do
    send self(), :usage
    {:reply, :ok, state}
  end

  defp setup_queue(state) do
    Upgrades.create_queue(%{
      git: Console.conf(:git_url),
      domain: Console.conf(:url),
      name: Console.conf(:cluster_name),
      legacy: !Console.byok?() && !Console.cloud?(),
      provider: to_provider(Console.conf(:provider))
    })
    |> case do
      {:ok, %{id: id}} ->
        Process.send_after(self(), :connect, 1000)
        {:ok, _pid} = Plural.start_wss()
        {:ok, ref} = :timer.send_interval(@poll_interval, :next)
        {:ok, _} = :timer.send_interval(@resource_interval, :svcs)
        {:noreply, %{state | queue_id: id, timer: ref}}
      err ->
        Logger.error "failed to create upgrade queue: #{inspect(err)}"
        Process.send_after(self(), :start, :timer.seconds(5))
        {:noreply, state}
    end
  end

  def handle_info(:start, state) do
    Logger.info "starting upgrades watcher"
    Logger.info "provider info: #{System.get_env("PROVIDER")}"

    case Console.Features.check_license() do
      :ignore -> setup_queue(state)
      _ ->
        Logger.info "Bypass configuring upgrade queue for sandboxed instance"
        {:noreply, state}
    end
  end

  def handle_info(:connect, state) do
    Logger.info "Joining upgrade queue channel"
    case Socket.do_join("queues:#{state.queue_id}") do
      :ok ->
        send self(), :next
        {:noreply, %{state | upgrades: "queues:#{state.queue_id}"}}
      error ->
        Logger.error "Failed to join upgrade room: #{inspect(error)}"
        Process.send_after(self(), :connect, 1000)
        {:noreply, state}
    end
  end

  # def handle_info(:next, %{upgrades: upgrades} = state) do
  #   with {:ok, %{"id" => id} = result} <- Socket.do_push(upgrades, "next", %{}),
  #        true <- Console.Bootstrapper.git_enabled?() do
  #     start_transaction()
  #     |> add_operation(:build, fn _ -> Handlers.Upgrade.create_build(result) end)
  #     |> add_operation(:ack, fn _ -> Socket.do_push(upgrades, "ack", %{"id" => id}) end)
  #     |> execute()
  #     |> case do
  #       {:ok, _} -> {:noreply, %{state | last: id}}
  #       _ -> {:noreply, state} # add some retry logic?
  #     end
  #   else
  #     error ->
  #       Logger.info "Failed to deliver upgrade: #{inspect(error)}"
  #       {:noreply, state}
  #   end
  # end

  def handle_info(:svcs, %{upgrades: nil} = state), do: {:noreply, state}
  def handle_info(:svcs, %{upgrades: upgrades} = state) do
    with {:ok, summary} <- Info.fetch() do
      svcs = Services.count()
      Socket.do_push(upgrades, "usage", Map.put(summary, :services, svcs))
      {:noreply, state}
    else
      err ->
        Logger.info "Did not report usage because of #{inspect(err)}"
        {:noreply, state}
    end
  end

  def handle_info(:usage, %{upgrades: nil} = state), do: {:noreply, state}
  def handle_info(:usage, %{upgrades: upgrades} = state) do
    Logger.info "Collecting resource usage"
    with {:ok, summary} <- Info.fetch() do
      Socket.do_push(upgrades, "usage", summary)
      {:noreply, state}
    else
      err ->
        Logger.info "Did not report usage because of #{inspect(err)}"
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp to_provider(:gcp), do: "GCP"
  defp to_provider(:aws), do: "AWS"
  defp to_provider(:azure), do: "AZURE"
  defp to_provider(:equinix), do: "EQUINIX"
  defp to_provider(_), do: "CUSTOM"
end
