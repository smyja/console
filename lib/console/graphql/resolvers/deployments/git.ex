defmodule Console.GraphQl.Resolvers.Deployments.Git do
  use Console.GraphQl.Resolvers.Deployments.Base
  alias Console.Deployments.Git
  alias Console.Deployments.Helm.Repository
  alias Console.Schema.{
    GitRepository,
    PrAutomation,
    ScmConnection,
    PullRequest,
    ScmWebhook,
    DependencyManagementService
  }

  def resolve_scm_connection(%{id: id}, _), do: {:ok, Git.get_scm_connection(id)}
  def resolve_scm_connection(%{name: name}, _), do: {:ok, Git.get_scm_connection_by_name(name)}

  def resolve_pr_automation(%{id: id}, _), do: {:ok, Git.get_pr_automation(id)}
  def resolve_pr_automation(%{name: name}, _), do: {:ok, Git.get_pr_automation_by_name(name)}

  def resolve_git(%{id: id}, %{context: %{current_user: user}}) when is_binary(id) do
    Git.get_repository(id)
    |> allow(user, :read)
  end

  def resolve_git(%{url: url}, %{context: %{current_user: user}}) do
    Git.get_by_url(url)
    |> allow(user, :read)
  end

  def list_git_repositories(args, _) do
    GitRepository.ordered()
    |> paginate(args)
  end

  def list_scm_connections(args, _) do
    ScmConnection.ordered()
    |> paginate(args)
  end

  def list_pr_automations(args, _) do
    PrAutomation.ordered()
    |> paginate(args)
  end

  def list_pull_requests(args, _) do
    PullRequest.ordered()
    |> maybe_search(PullRequest, args)
    |> pr_filters(args)
    |> paginate(args)
  end

  def list_scm_webhooks(args, _) do
    ScmWebhook.ordered()
    |> paginate(args)
  end

  def list_dependency_management_services(args, _) do
    DependencyManagementService.ordered()
    |> paginate(args)
  end

  def get_helm_repository(%{name: name, namespace: ns}, _), do: Kube.Client.get_helm_repository(ns, name)

  def list_helm_repositories(_, _), do: Git.list_helm_repositories()

  def helm_charts(helm, _, _), do: Repository.charts(helm)

  def helm_status(helm, _, _), do: Repository.status(helm)

  def git_refs(git), do: Git.Discovery.refs(git)

  def create_git_repository(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_repository(attrs, user)

  def update_git_repository(%{id: id, attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.update_repository(attrs, id, user)

  def delete_git_repository(%{id: id}, %{context: %{current_user: user}}),
    do: Git.delete_repository(id, user)

  def create_scm_connection(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_scm_connection(attrs, user)

  def update_scm_connection(%{id: id, attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.update_scm_connection(attrs, id, user)

  def delete_scm_connection(%{id: id}, %{context: %{current_user: user}}),
    do: Git.delete_scm_connection(id, user)

  def create_pr_automation(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_pr_automation(attrs, user)

  def update_pr_automation(%{id: id, attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.update_pr_automation(attrs, id, user)

  def delete_pr_automation(%{id: id}, %{context: %{current_user: user}}),
    do: Git.delete_pr_automation(id, user)

  def create_pull_request(%{id: id, branch: branch, context: ctx} = args, %{context: %{current_user: user}}),
    do: Git.create_pull_request(%{}, ctx, id, branch, args[:identifier], user)

  def create_pr(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_pull_request(attrs, user)

  def update_pr(%{attributes: attrs, id: id}, %{context: %{current_user: user}}),
    do: Git.update_pr(attrs, id, user)

  def delete_pr(%{id: id}, %{context: %{current_user: user}}),
    do: Git.delete_pr(id, user)

  def create_webhook_for_connection(%{owner: owner, connection_id: conn_id}, %{context: %{current_user: user}}),
    do: Git.create_webhook_for_connection(owner, conn_id, user)

  def create_webhook(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_webhook(attrs, user)

  def setup_renovate(%{connection_id: id, repos: repos} = args, %{context: %{current_user: user}}),
    do: Git.setup_renovate(args, id, repos, user)

  def reconfigure_renovate(%{repos: repos, service_id: svc_id}, %{context: %{current_user: user}}),
    do: Git.reconfigure_renovate(%{repositories: repos}, svc_id, user)

  defp pr_filters(query, args) do
    Enum.reduce(args, query, fn
      {:cluster_id, cid}, q -> PullRequest.for_cluster(q, cid)
      {:service_id, sid}, q -> PullRequest.for_service(q, sid)
      {:open, true}, q -> PullRequest.open(q)
      {:q, search}, q -> PullRequest.search(q, search)
      _, q -> q
    end)
  end
end
