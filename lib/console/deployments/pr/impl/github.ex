defmodule Console.Deployments.Pr.Impl.Github do
  import Console.Deployments.Pr.Utils
  alias Console.Deployments.Pr.File
  alias Console.Schema.{PrAutomation, PullRequest, ScmWebhook, ScmConnection}
  alias Console.Jwt.Github
  require Logger

  @behaviour Console.Deployments.Pr.Dispatcher

  def create(pr, branch, ctx) do
    with {:ok, client} <- client(pr),
         {:ok, owner, repo} <- identifier(pr),
         {:ok, title, body} <- description(pr, ctx) do
      Tentacat.Pulls.create(client, owner, repo, %{
        head: branch,
        title: title,
        body: body,
        base: pr.branch || "main",
      })
      |> case do
        {_, %{"html_url" => url} = result, _} ->
          {:ok, %{title: title, url: url, body: body, ref: branch, owner: owner(result)}}
        {_, body, _} -> {:error, "failed to create pull request: #{Jason.encode!(body)}"}
      end
    end
  end

  def webhook(%ScmConnection{} = conn, %ScmWebhook{owner: owner, hmac: hmac} = hook) do
    with {:ok, client} <- client(conn) do
      Tentacat.Organizations.Hooks.create(client, owner, %{
        "name" => "web",
        "active" => true,
        "events" => ["*"],
        "config" => %{
          "url" => ScmWebhook.url(hook),
          "content_type" => "json",
          "secret" => hmac,
        },
      })
      |> case do
        {_, %{"id" => _}, _} -> :ok
        {_, body, _} -> {:error, "failed to create webhook: #{Jason.encode!(body)}"}
      end
    end
  end

  def pr(%{"pull_request" => %{"html_url" => url} = pr} = event) do
    attrs = Map.merge(%{
      status: state(pr),
      ref: pr["head"]["ref"],
      title: pr["title"],
      body: pr["body"],
      commit_sha: pr["head"]["sha"]
    }, pr_associations(pr_content(pr)))
    |> add_approver(event)
    |> Console.drop_nils()

    {:ok, url, attrs}
  end
  def pr(_), do: :ignore

  defp add_approver(attrs, %{"review" => %{"state" => "approved", "user" => u}}),
    do: Map.put(attrs, :approver, u["email"] || u["login"])
  defp add_approver(attrs, _), do: attrs

  def review(conn, %PullRequest{url: url} = pr, body) do
    with {:ok, owner, repo, number} <- get_pull_id(url),
         {:ok, client} <- client(conn),
         body = %{"body" => filter_ansi(body), "event" => "COMMENT"} do

      case pr do
        %PullRequest{comment_id: id} when is_binary(id) ->
          Tentacat.put("repos/#{owner}/#{repo}/pulls/#{number}/reviews/#{id}", client, Map.delete(body, "event"))
        _ -> Tentacat.Pulls.Reviews.create(client, owner, repo, number, body)
      end
      |> case do
        {_, %{"id" => id}, _} -> {:ok, "#{id}"}
        {_, body, _} -> {:error, "failed to create review comment: #{Jason.encode!(body)}"}
      end
    end
  end

  def approve(conn, %PullRequest{url: url}, body) do
    with {:ok, owner, repo, number} <- get_pull_id(url),
         {:ok, client} <- client(conn),
         body = %{"body" => filter_ansi(body), "event" => "APPROVE"} do
      case Tentacat.Pulls.Reviews.create(client, owner, repo, number, body) do
        {_, %{"id" => id}, _} -> {:ok, "#{id}"}
        {_, body, _} -> {:error, "failed to create review comment: #{Jason.encode!(body)}"}
      end
    end
  end

  def files(conn, url) do
    with {:ok, owner, repo, number} <- get_pull_id(url),
         {:ok, client} <- client(conn),
         {_, %{} = pr, _} <- Tentacat.Pulls.find(client, owner, repo, number),
         {_, [_ | _] = files, _} <- Tentacat.Pulls.Files.list(client, owner, repo, number) do
      {:ok, to_files(client, url, pr, files)}
    else
      err ->
        Logger.info("failed to list pr files #{inspect(err)}")
        err
    end
  end

  def pr_info(url) do
    with {:ok, owner, repo, number} <- get_pull_id(url) do
      {:ok, %{owner: owner, repo: repo, number: number}}
    end
  end

  defp pr_content(pr), do: "#{pr["head"]["ref"]}\n#{pr["title"]}\n#{pr["body"] || ""}"

  defp to_files(client, url, pr, files) do
    Enum.map(files, fn f ->
      %File{
        url: url,
        repo: to_repo_url(url),
        title: pr["title"],
        contents: get_content(client, f["contents_url"]),
        filename: f["filename"],
        sha: f["sha"],
        patch: f["patch"],
        base: get_in(pr, ~w(base ref)),
        head: get_in(pr, ~w(head ref))
      }
    end)
    |> Enum.filter(&File.valid?/1)
  end

  defp get_content(client, url) when is_binary(url) do
    headers = [{"authorization", "Token #{client.auth.access_token}"}]
    with {:ok, %HTTPoison.Response{status_code: 200, body: content}} <- HTTPoison.get(url, headers),
         {:ok, %{"content" => content}} <- Jason.decode(content) do
      String.split(content)
      |> Enum.map(fn line ->
        case Base.decode64(line) do
          {:ok, l} -> l
          _ -> nil
        end
      end)
      |> Enum.join("")
    else
      _ -> nil
    end
  end
  defp get_content(_, _), do: nil

  defp identifier(%PrAutomation{identifier: id}) when is_binary(id) do
    case String.split(id, "/") do
      [owner, repo] -> {:ok, owner, repo}
      _ -> {:error, "could not parse repo identifier #{id}"}
    end
  end

  defp client(pr) do
    case url_and_token(pr, :pass) do
      {:ok, url, nil} -> fetch_app_token(url, pr)
      {:ok, :pass, token} -> {:ok, Tentacat.Client.new(%{access_token: token})}
      {:ok, url, token} -> {:ok, Tentacat.Client.new(%{access_token: token}, url)}
      err -> err
    end
  end

  defp fetch_app_token(url, %PrAutomation{connection: %ScmConnection{} = conn}),
    do: fetch_app_token(url, conn)
  defp fetch_app_token(url, %ScmConnection{github: %{app_id: app_id, installation_id: inst_id, private_key: pk}}),
    do: Github.gh_client(url, app_id, inst_id, pk)
  defp fetch_app_token(_, _), do: {:error, "could not find github app credentials on this connection"}

  defp owner(%{"user" => %{"login" => owner}}), do: owner
  defp owner(_), do: nil

  defp state(%{"merged" => true}), do: :merged
  defp state(%{"state" => "closed", "merged_at" => merged}) when not is_nil(merged), do: :merged
  defp state(%{"state" => "closed"}), do: :closed
  defp state(_), do: :open

  defp to_repo_url(url) do
    case String.split(url, "/pull") do
      [repo | _] -> "#{repo}.git"
      _ -> url
    end
  end

  defp get_pull_id(url) do
    with %URI{path: "/" <> path} <- URI.parse(url),
         [owner, repo, "pull", number] <- String.split(path, "/") do
      {:ok, owner, repo, number}
    else
      _ -> {:error, "could not parse github url"}
    end
  end
end
