defmodule Watchman.Services.Builds do
  use Watchman.Services.Base
  alias Watchman.PubSub
  alias Kube.{Client, Application}
  alias Watchman.Schema.{Build, Command, User, Changelog, Lock}

  def get!(id), do: Repo.get!(Build, id)

  def get(id), do: Repo.get(Build, id)

  def lock(name, id) do
    start_transaction()
    |> add_operation(:lock, fn _ ->
      Lock.active()
      |> Repo.get_by(name: name)
      |> case do
        nil -> {:ok, nil}
        _ -> {:error, :locked}
      end
    end)
    |> add_operation(:create, fn _ ->
      %Lock{name: name, holder: id}
      |> Lock.changeset(%{expires_at: Timex.now() |> Timex.shift(minutes: 30)})
      |> Repo.insert(on_conflict: :replace_all, conflict_target: [:name])
    end)
    |> execute(extract: :create)
  end

  def unlock(name, id) do
    start_transaction()
    |> add_operation(:lock, fn _ ->
      case Repo.get_by(Lock, name: name, holder: id) do
        %Lock{} = lock -> {:ok, lock}
        _ -> {:error, :locked}
      end
    end)
    |> add_operation(:delete, fn %{lock: lock} -> Repo.delete(lock) end)
    |> execute(extract: :delete)
  end

  def create(attrs, %User{id: id}) do
    start_transaction()
    |> add_operation(:build, fn _ ->
      %Build{type: :deploy, status: :queued, creator_id: id}
      |> Build.changeset(attrs)
      |> Repo.insert()
    end)
    |> add_operation(:valid, fn %{build: %{repository: repo} = build} ->
      case Client.get_application(repo) do
        {:ok, %Application{}} -> {:ok, build}
        _ -> {:error, :invalid_repository}
      end
    end)
    |> execute(extract: :build)
    |> when_ok(&wake_deployer/1)
    |> when_ok(&broadcast(&1, :create))
  end

  def cancel(%Build{id: id}) do
    start_transaction()
    |> add_operation(:build, fn _ -> {:ok, get(id)} end)
    |> add_operation(:update, fn
      %{build: %{status: :running} = build} ->
        modify_status(build, :cancelled)
      %{build: build} -> {:ok, build}
    end)
    |> execute(extract: :update)
    |> when_ok(&broadcast(&1, :update))
  end

  def cancel(build_id) do
    get!(build_id)
    |> modify_status(:cancelled)
    |> notify(:delete)
    |> when_ok(&broadcast(&1, :update))
  end

  def create_command(attrs, %Build{id: id}) do
    %Command{build_id: id}
    |> Command.changeset(attrs)
    |> Repo.insert()
    |> when_ok(&broadcast(&1, :create))
  end

  def complete(%Command{stdout: stdout} = command, exit_code) do
    %{command | stdout: nil}
    |> Command.changeset(%{
      exit_code: exit_code,
      completed_at: Timex.now(),
      stdout: stdout
    })
    |> Repo.update()
    |> when_ok(&broadcast(&1, :update))
  end

  def poll() do
    Build.queued()
    |> Build.first()
    |> Build.ordered(desc: :inserted_at)
    |> Repo.one()
  end

  def running(build),
    do: modify_status(build, :running)

  def pending(build) do
    start_transaction()
    |> add_operation(:build, fn _ ->
      modify_status(build, :pending)
    end)
    |> add_changelogs()
    |> execute(extract: :build)
    |> when_ok(&broadcast(&1, :update))
    |> notify(:pending)
  end

  def approve(build_id, %User{id: user_id}) do
    get!(build_id)
    |> Build.changeset(%{
      approver_id: user_id,
      status: :running
    })
    |> Repo.update()
    |> when_ok(&broadcast(&1, :update))
    |> notify(:approve)
  end

  def succeed(build) do
    storage = Watchman.storage()
    start_transaction()
    |> add_operation(:build, fn _ ->
      modify_status(build, :successful)
    end)
    |> add_changelogs()
    |> add_operation(:sha, fn %{build: build} ->
      with {:ok, sha} <- storage.revision() do
        build
        |> Build.changeset(%{sha: sha})
        |> Repo.update()
      end
    end)
    |> execute(extract: :sha)
    |> when_ok(&broadcast(&1, :update))
    |> notify(:succeed)
  end

  def fail(build) do
    start_transaction()
    |> add_operation(:build, fn _ ->
      modify_status(build, :failed)
    end)
    |> add_changelogs()
    |> execute(extract: :build)
    |> when_ok(&broadcast(&1, :update))
    |> notify(:failed)
  end

  defp add_changelogs(transaction) do
    diff_folder = Watchman.workspace() |>  Path.join("diffs")
    with {:ok, [_ | _] = subfolders} <- File.ls(diff_folder) do
      subfolders
      |> Enum.map(& {&1, Path.join(diff_folder, &1) |> File.ls()})
      |> Enum.flat_map(fn
        {repo, {:ok, contents}} -> Enum.map(contents, & {repo, &1})
        _ -> []
      end)
      |> Enum.reduce(transaction, fn {repo, diff_file}, transaction ->
        add_operation(transaction, diff_file, fn %{build: %{id: id}} ->
          add_changelog(repo, Path.join([diff_folder, repo, diff_file]), id)
        end)
      end)
    else
      _ -> transaction
    end
  end

  defp add_changelog(repo, diff, build_id) do
    %Changelog{build_id: build_id}
    |> Changelog.changeset(%{
      repo: repo,
      tool: Path.basename(diff),
      content: File.read!(diff)
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:build_id, :repo, :tool])
  end

  defp modify_status(build, state) do
    cleaned(build)
    |> Build.changeset(add_completion(%{status: state}, state))
    |> Repo.update()
  end

  defp add_completion(attrs, state) when state in [:successful, :failed],
    do: Map.put(attrs, :completed_at, Timex.now())
  defp add_completion(attrs, _), do: attrs

  defp wake_deployer(build) do
    Watchman.Deployer.wake()
    {:ok, build}
  end

  defp cleaned(build), do: %{build | changelogs: %Ecto.Association.NotLoaded{}}

  defp notify({:ok, %Build{} = build}, :succeed),
    do: handle_notify(PubSub.BuildSucceeded, build)
  defp notify({:ok, %Build{} = build}, :failed),
    do: handle_notify(PubSub.BuildFailed, build)
  defp notify({:ok, %Build{} = build}, :pending),
    do: handle_notify(PubSub.BuildPending, build)
  defp notify({:ok, %Build{} = build}, :approve),
    do: handle_notify(PubSub.BuildApproved, build)
  defp notify({:ok, %Build{} = build}, :delete),
    do: handle_notify(PubSub.BuildDeleted, build)
  defp notify(error, _), do: error
end