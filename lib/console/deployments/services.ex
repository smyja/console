defmodule Console.Deployments.Services do
  use Console.Services.Base
  import Console.Deployments.Policies
  alias Console.PubSub
  alias Console.Schema.{Service, ServiceComponent, Revision, User, Cluster, ClusterProvider, ApiDeprecation}
  alias Console.Deployments.{Secrets.Store, Git, Clusters, Deprecations.Checker, AddOns}
  require Logger

  @type service_resp :: {:ok, Service.t} | Console.error
  @type revision_resp :: {:ok, Revision.t} | Console.error

  def get_service!(id), do: Console.Repo.get!(Service, id)

  def get_service(id), do: Console.Repo.get(Service, id)

  def get_service_by_name!(cid, name), do: Console.Repo.get_by!(Service, name: name, cluster_id: cid)
  def get_service_by_name(cid, name), do: Console.Repo.get_by(Service, name: name, cluster_id: cid)

  def get_service_by_handle!(handle, name) do
    Service.for_cluster_handle(handle)
    |> Repo.get_by!(name: name)
  end

  def get_revision!(id), do: Repo.get!(Revision, id)

  def tarball(%Service{id: id}), do: api_url("v1/git/tarballs?id=#{id}")

  def referenced?(id) do
    Enum.map([Cluster.for_service(id), ClusterProvider.for_service(id)], &Console.Repo.exists?/1)
    |> Enum.any?(& &1)
  end

  def count() do
    Service.nonsystem()
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Creates a new service in a cluster, alongside an initial revision for the service
  """
  @spec create_service(map, binary, User.t) :: service_resp
  def create_service(attrs, cluster_id, %User{} = user) do
    start_transaction()
    |> add_operation(:check, fn _ ->
      Clusters.get_cluster(cluster_id)
      |> allow(user, :write)
      |> case do
        {:ok, %Cluster{deleted_at: nil} = cluster} -> {:ok, cluster}
        {:ok, _} -> {:error, "cannot create a service in a deleting cluster"}
        err -> err
      end
    end)
    |> add_operation(:base, fn _ ->
      %Service{cluster_id: cluster_id}
      |> Service.changeset(add_version(attrs, "0.0.1"))
      |> Console.Repo.insert()
    end)
    |> add_operation(:revision, fn %{base: base} -> create_revision(add_version(attrs, "0.0.1"), base) end)
    |> add_revision()
    |> execute(extract: :service)
    |> notify(:create, user)
  end

  @doc """
  modifies rbac settings for this service
  """
  @spec rbac(map, binary, User.t) :: service_resp
  def rbac(attrs, service_id, %User{} = user) do
    get_service!(service_id)
    |> Repo.preload([:write_bindings, :read_bindings])
    |> allow(user, :write)
    |> when_ok(&Service.rbac_changeset(&1, attrs))
    |> when_ok(:update)
    |> notify(:update, user)
  end

  def operator_service(%Cluster{id: cluster_id} = cluster, %User{} = user) do
    repo = Git.deploy_repo!()
    create_service(%{
      repository_id: repo.id,
      protect: true,
      name: "deploy-operator",
      namespace: "plrl-deploy-operator",
      git: %{ref: "main", folder: "charts/deployment-operator"},
      configuration: operator_configuration(cluster)
    }, cluster_id, user)
  end

  def update_operator_service(%Cluster{id: id} = cluster, %User{} = user) do
    case get_service_by_name(id, "deploy-operator") do
      %Service{} = svc ->
        merge_service(operator_configuration(cluster), svc.id, user)
      _ -> {:ok, nil}
    end
  end

  defp operator_configuration(%Cluster{id: cluster_id, deploy_token: deploy_token}) do
    [
      %{name: "clusterId", value: cluster_id},
      %{name: "deployToken", value: deploy_token},
      %{name: "url", value: api_url("gql")},
      %{name: "kasAddress", value: Clusters.kas_url()}
    ]
  end

  @spec authorized(binary, Cluster.t | User.t) :: service_resp
  def authorized(%Service{} = svc, %User{} = user), do: allow(svc, user, :read)
  def authorized(%Service{cluster_id: id} = svc, %Cluster{id: id}), do: {:ok, svc}
  def authorized(service_id, actor) when is_binary(service_id) do
    get_service(service_id)
    |> authorized(actor)
  end
  def authorized(_, _), do: {:error, "could not find service in cluster"}

  def add_errors(%Service{id: svc_id}, errors) do
    get_service(svc_id)
    |> Repo.preload([:errors])
    |> Service.changeset(%{errors: errors})
    |> Repo.update()
  end

  @doc """
  Updates a service and creates a new revision
  """
  @spec update_service(map, binary, User.t) :: service_resp
  def update_service(attrs, service_id, %User{} = user) do
    start_transaction()
    |> add_operation(:check, fn _ ->
      get_service!(service_id)
      |> allow(user, :write)
    end)
    |> add_operation(:update, fn %{check: svc} -> update_service(attrs, svc) end)
    |> execute(extract: :update)
    |> notify(:update, user)
  end

  def accessible(%Service{} = svc, k8s_resource) do
    %{components: components} = Repo.preload(svc, [:components])
    {g, v, k, ns, n} = Kube.Utils.identifier(k8s_resource)

    Enum.any?(components, fn
      %ServiceComponent{group: ^g, version: ^v, kind: ^k, namespace: ^ns, name: ^n} -> true
      _ -> false
    end)
    |> case do
      true -> {:ok, k8s_resource}
      _ -> {:error, "forbidden"}
    end
  end
  def accessible(_, _), do: {:error, "forbidden"}

  @doc """
  It will merge in new configuration for a service (and nothing else)
  """
  @spec merge_service(list, binary, User.t) :: service_resp
  def merge_service(config, service_id, %User{} = user) do
    start_transaction()
    |> add_operation(:source, fn _ ->
      get_service!(service_id)
      |> allow(user, :write)
    end)
    |> add_operation(:config, fn %{source: source} ->
      with {:ok, secrets} <- configuration(source),
        do: {:ok, merge_configuration(secrets, config)}
    end)
    |> add_operation(:update, fn %{source: source, config: config} ->
      update_service(%{configuration: config}, source)
    end)
    |> execute(extract: :update)
    |> notify(:update, user)
  end

  @doc """
  Will copy a service, and apply any user specified attributes on top.

  This will also merge user specified configuration into the services base config (allowing you not to have to specify the full set)
  """
  @spec clone_service(map, binary, binary, User.t) :: service_resp
  def clone_service(attrs \\ %{}, service_id, cluster_id, %User{} = user) do
    start_transaction()
    |> add_operation(:source, fn _ ->
      get_service!(service_id)
      |> allow(user, :write)
    end)
    |> add_operation(:config, fn %{source: source} ->
      with {:ok, secrets} <- configuration(source),
        do: {:ok, merge_configuration(secrets, attrs[:configuration])}
    end)
    |> add_operation(:create, fn %{source: source, config: config} ->
      Map.take(source, [:repository_id, :sha, :name, :namespace])
      |> Map.put(:git, Map.from_struct(source.git))
      |> Map.merge(attrs)
      |> Map.put(:configuration, config)
      |> create_service(cluster_id, user)
    end)
    |> execute(extract: :create)
    |> notify(:create, user)
  end

  @doc """
  Updates the sha of a service if relevant
  """
  @spec update_sha(Service.t, binary, binary) :: service_resp
  def update_sha(%Service{sha: sha} = svc, sha, _), do: {:ok, svc}
  def update_sha(%Service{id: id}, sha, msg) do
    start_transaction()
    |> add_operation(:base, fn _ ->
      get_service!(id)
      |> Service.changeset(%{sha: sha, status: :stale, message: msg})
      |> Repo.update()
    end)
    |> add_operation(:current, fn %{base: base} ->
      case Repo.preload(base, [:revision]) do
        %{revision: %Revision{} = revision} ->
          Revision.update_changeset(revision, %{sha: sha, message: msg})
          |> Repo.update()
        _ -> {:ok, base}
      end
    end)
    |> add_operation(:revision, fn %{base: base} ->
      add_version(%{sha: sha, message: msg}, base.version)
      |> Console.dedupe(:git, %{ref: sha, folder: base.git.folder})
      |> Console.dedupe(:configuration, fn ->
        {:ok, secrets} = configuration(base)
        Enum.map(secrets, fn {k, v} -> %{name: k, value: v} end)
      end)
      |> create_revision(base)
    end)
    |> execute(extract: :base)
    |> notify(:update, :ignore)
  end

  def update_service(attrs, svc_id) when is_binary(svc_id),
    do: update_service(attrs, get_service!(svc_id))
  def update_service(attrs, %Service{} = svc) do
    start_transaction()
    |> add_operation(:base, fn _ ->
      Service.changeset(svc, Map.put(attrs, :status, :stale))
      |> Console.Repo.update()
    end)
    |> add_operation(:revision, fn %{base: base} ->
      add_version(attrs, base.version)
      |> Console.dedupe(:git, Map.take(base.git, ~w(ref folder)a))
      |> Console.dedupe(:configuration, fn ->
        {:ok, secrets} = configuration(base)
        Enum.map(secrets, fn {k, v} -> %{name: k, value: v} end)
      end)
      |> create_revision(base)
    end)
    |> add_revision()
    |> execute(extract: :service)
  end

  defp add_version(attrs, vsn), do: Console.dedupe(attrs, :version, vsn)

  @doc """
  fetches the docs for a given service out of git, and renders them as a list of file path/content pairs
  """
  @spec docs(Service.t) :: [%{path: binary, content: binary}]
  def docs(%Service{} = svc) do
    with {:ok, f} <- Git.Discovery.docs(svc),
         {:ok, res} <- AddOns.tar_stream(f) do
      {:ok, Enum.map(res, fn {name, content} -> %{path: name, content: content} end)}
    else
      err ->
        Logger.info "failed to fetch docs tarball: #{inspect(err)}"
        {:error, "could not fetch docs"}
    end
  end

  @doc """
  Rollbacks a service to a given revision id, all configuration will then be fetched via that revision
  and modify the sha/git pointers as well.
  """
  @spec rollback(binary, binary, User.t) :: service_resp
  def rollback(revision_id, service_id, %User{} = user) do
    start_transaction()
    |> add_operation(:service, fn _ ->
      get_service!(service_id)
      |> allow(user, :write)
    end)
    |> add_operation(:revision, fn %{service: %{id: id}} ->
      case get_revision!(revision_id) do
        %Revision{service_id: ^id} = r -> {:ok, r}
        _ -> {:error, "revision does not belong to this service"}
      end
    end)
    |> add_operation(:update, fn %{service: svc, revision: rev} ->
      svc
      |> Service.rollback_changeset(%{
        status: :stale,
        revision_id: rev.id,
        sha: rev.sha,
        git: Map.take(rev.git, [:ref, :folder])
      })
      |> Repo.update()
    end)
    |> execute(extract: :update)
    |> notify(:update, user)
  end

  @doc """
  Updates the list of service components, separate operation to avoid creating a no-op revision
  """
  @spec update_components(map, binary | Service.t) :: service_resp
  def update_components(attrs, %Service{} = service) do
    start_transaction()
    |> add_operation(:service, fn _ ->
      svc = Console.Repo.preload(service, [:components, :errors])

      svc
      |> Service.changeset(stabilize(attrs, svc))
      |> Console.Repo.update()
    end)
    |> add_operation(:deprecations, fn %{service: svc} -> add_deprecations(svc) end)
    |> add_operation(:updated, fn %{service: %Service{components: components} = service} ->
      running = Enum.all?(components, & &1.state == :running || is_nil(&1.state))
      failed = Enum.any?(components, & &1.state == :failed)
      unsynced = Enum.any?(components, & !&1.synced)
      num_healthy = Enum.count(components, & (&1.state == :running || is_nil(&1.state)) && &1.synced)
      component_status = "#{num_healthy} / #{length(components)}"
      case {failed, running, unsynced} do
        {true, _, _} -> update_status(service, :failed, component_status)
        {_, _, true} -> update_status(service, :stale, component_status)
        {_, true, _} -> update_status(service, :healthy, component_status)
        _ -> update_status(service, :stale, component_status)
      end
    end)
    |> execute(extract: :updated)
    |> notify(:components)
  end
  def update_components(attrs, service_id) when is_binary(service_id),
    do: update_components(attrs, get_service!(service_id))

  @spec update_components(map, binary, Cluster.t) :: service_resp
  def update_components(attrs, service_id, %Cluster{} = cluster) do
    with {:ok, svc} <- authorized(service_id, cluster),
      do: update_components(attrs, svc)
  end

  defp stabilize(%{components: new_components} = attrs, %{components: components}) do
    components = Map.new(components, fn %{id: id} = comp -> {component_key(comp), id} end)
    new_components = Enum.map(new_components, &Map.put(&1, :id, components[component_key(&1)]))
    Map.put(attrs, :components, new_components)
  end
  defp stabilize(attrs, _), do: attrs

  defp component_key(%{group: g, version: v, kind: k, namespace: ns, name: n}), do: {g, v, k, ns, n}

  @doc """
  Find and insert any deprecations for this service's components
  """
  @spec add_deprecations(Service.t) :: {:ok, map} | Console.error
  def add_deprecations(%Service{} = service) do
    %{components: components, cluster: cluster} = Repo.preload(service, [:components, :cluster])
    xact = add_operation(start_transaction(), :wipe, fn _ ->
      ApiDeprecation.for_service(service.id)
      |> Repo.delete_all()
      |> ok()
    end)

    Enum.reduce(components, xact, fn component, xact ->
      case Checker.check(component, cluster) do
        {entry, blocking} ->
          add_operation(xact, component.id, fn _ ->
            attrs = Map.from_struct(entry) |> Map.put(:blocking, blocking)
            %ApiDeprecation{component_id: component.id}
            |> ApiDeprecation.changeset(attrs)
            |> Repo.insert()
          end)
        _ -> xact
      end
    end)
    |> execute()
  end

  @doc """
  Schedules a service to be cleaned up and ultimately deleted
  """
  @spec delete_service(binary, User.t) :: service_resp
  def delete_service(service_id, %User{} = user) do
    get_service!(service_id)
    |> Ecto.Changeset.change(%{deleted_at: Timex.now()})
    |> allow(user, :delete)
    |> when_ok(:update)
    |> notify(:delete, user)
  end

  def force_delete_service(service_id, %User{} = user) do
    get_service!(service_id)
    |> Ecto.Changeset.change(%{deleted_at: Timex.now()})
    |> Repo.update()
    |> notify(:delete, user)
  end

  @doc """
  permissionless service delete for internal usage
  """
  @spec delete_service(binary) :: service_resp
  def delete_service(service_id) do
    get_service!(service_id)
    |> Ecto.Changeset.change(%{deleted_at: Timex.now()})
    |> Console.Repo.update()
    |> notify(:delete)
  end

  @doc """
  Permanently removes a service from the db along w/ all secrets
  """
  @spec hard_delete(Service.t) :: service_resp
  def hard_delete(%Service{} = svc) do
    Console.Repo.delete(svc)
    |> notify(:hard_delete)
  end

  @doc """
  Fetches a service's configuration from the configured store
  """
  @spec configuration(Service.t | Revision.t) :: Store.secrets_resp
  def configuration(%Service{revision_id: nil}), do: {:ok, %{}}
  def configuration(%Service{revision_id: revision_id}), do: secret_store().fetch(revision_id)
  def configuration(%Revision{id: id}), do: secret_store().fetch(id)

  @doc """
  fetches all revisions of a service
  """
  @spec revisions(Service.t) :: [Revision.t]
  def revisions(%Service{id: id}, limit \\ :none) do
    Revision.for_service(id)
    |> Revision.ordered()
    |> add_limit(limit)
    |> Console.Repo.all()
  end

  defp add_limit(q, :none), do: q
  defp add_limit(q, limit) when is_integer(limit), do: Revision.limit(q, limit)

  @doc """
  Prunes expired revisions for a service, and guarantees current revision remains (even if older)
  """
  @spec prune_revisions(Service.t) :: {:ok, integer}
  def prune_revisions(%Service{id: id, revision_id: rid} = service) do
    to_keep = revisions(service, Console.conf(:revision_history_limit))
    to_keep = MapSet.new([rid | Enum.map(to_keep, & &1.id)])
              |> MapSet.to_list()

    Revision.ignore_ids(to_keep)
    |> Revision.for_service(id)
    |> Repo.delete_all()
    |> elem(0)
    |> ok()
  end

  defp create_revision(attrs, %Service{id: id}) do
    start_transaction()
    |> add_operation(:revision, fn _ ->
      %Revision{service_id: id}
      |> Revision.changeset(attrs)
      |> Console.Repo.insert()
    end)
    |> add_operation(:secrets, fn %{revision: %{id: id}} ->
      secrets = Enum.into(attrs[:secrets] || [], %{}, & {&1.name, &1.value})
      secret_store().store(id, secrets)
    end)
    |> execute(extract: :revision)
  end

  defp add_revision(xact) do
    add_operation(xact, :service, fn %{revision: %{id: id}, base: service} ->
      Ecto.Changeset.change(service, %{revision_id: id})
      |> Console.Repo.update()
    end)
  end

  defp update_status(%Service{} = svc, status, component_status) do
    Ecto.Changeset.change(svc, %{status: status, component_status: component_status})
    |> Repo.update()
  end

  def api_url(path) do
    Path.join([Console.conf(:ext_url), "ext", path])
  end

  def merge_configuration(secrets, [_ | _] = config) do
    Enum.reduce(config, secrets, fn
      %{name: k, value: nil}, acc -> Map.delete(acc, k)
      %{name: k, value: v}, acc -> Map.put(acc, k, v)
    end)
    |> merge_configuration(nil)
  end
  def merge_configuration(secrets, _), do: Enum.map(secrets, fn {k, v} -> %{name: k, value: v} end)

  defp secret_store(), do: Console.conf(:secret_store)

  defp notify({:ok, %Service{} = svc}, :create, user),
    do: handle_notify(PubSub.ServiceCreated, svc, actor: user)
  defp notify({:ok, %Service{} = svc}, :update, user),
    do: handle_notify(PubSub.ServiceUpdated, svc, actor: user)
  defp notify({:ok, %Service{} = svc}, :delete, user),
    do: handle_notify(PubSub.ServiceDeleted, svc, actor: user)
  defp notify(pass, _, _), do: pass

  defp notify({:ok, %Service{} = svc}, :components),
    do: handle_notify(PubSub.ServiceComponentsUpdated, svc)
  defp notify({:ok, %Service{} = svc}, :update),
    do: handle_notify(PubSub.ServiceUpdated, svc)
  defp notify({:ok, %Service{} = svc}, :hard_delete),
    do: handle_notify(PubSub.ServiceHardDeleted, svc)
  defp notify(pass, _), do: pass
end