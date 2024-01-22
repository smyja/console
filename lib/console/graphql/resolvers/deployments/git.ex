defmodule Console.GraphQl.Resolvers.Deployments.Git do
  use Console.GraphQl.Resolvers.Deployments.Base
  alias Console.Deployments.Git
  alias Console.Deployments.Helm.Repository
  alias Console.Schema.{
    GitRepository,
    PrAutomation,
    ScmConnection,
    PullRequest
  }

  def resolve_scm_connection(%{id: id}, _), do: {:ok, Git.get_scm_connection(id)}

  def resolve_pr_automation(%{id: id}, _), do: {:ok, Git.get_pr_automation(id)}

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
    |> pr_filters(args)
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

  def create_pull_request(%{id: id, branch: branch, context: ctx}, %{context: %{current_user: user}}),
    do: Git.create_pull_request(ctx, id, branch, user)

  def create_pr(%{attributes: attrs}, %{context: %{current_user: user}}),
    do: Git.create_pull_request(attrs, user)

  defp pr_filters(query, args) do
    Enum.reduce(args, query, fn
      {:cluster_id, cid}, q -> PullRequest.for_cluster(q, cid)
      {:service_id, sid}, q -> PullRequest.for_service(q, sid)
      _, q -> q
    end)
  end
end