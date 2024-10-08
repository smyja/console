defmodule Console.Deployments.Pr.Impl.Github do
  import Console.Deployments.Pr.Utils
  alias Console.Schema.{PrAutomation, PullRequest, ScmWebhook, ScmConnection}
  alias Console.Jwt.Github
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
        {_, %{"html_url" => url} = body, _} ->
          {:ok, %{title: title, url: url, ref: branch, owner: owner(body)}}
        {_, body, _} -> {:error, "failed to create pull request: #{Jason.encode!(body)}"}
      end
    end
  end

  def webhook(%ScmConnection{} = conn, %ScmWebhook{owner: owner, hmac: hmac} = hook) do
    with {:ok, client} <- client(conn) do
      Tentacat.Organizations.Hooks.create(client, owner, %{
        "name" => "web",
        "active" => true,
        "events" => ["pull_request"],
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

  def pr(%{"pull_request" => %{"html_url" => url} = pr}) do
    attrs = Map.merge(%{
      status: state(pr),
      ref: pr["head"]["ref"],
      title: pr["title"],
      body: pr["body"]
    }, pr_associations(pr_content(pr)))
    |> Console.drop_nils()

    {:ok, url, attrs}
  end
  def pr(_), do: :ignore

  def review(conn, %PullRequest{url: url}, body) do
    with {:ok, owner, repo, number} <- get_pull_id(url),
         {:ok, client} <- client(conn) do
      case Tentacat.Pulls.Reviews.create(client, owner, repo, number, %{
            "body" => filter_ansi(body),
            "event" => "COMMENT"
      }) do
        {_, %{"id" => id}, _} -> {:ok, "#{id}"}
        {_, body, _} -> {:error, "failed to create review comment: #{Jason.encode!(body)}"}
      end
    end
  end

  defp pr_content(pr), do: "#{pr["head"]["ref"]}\n#{pr["title"]}\n#{pr["body"] || ""}"

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

  defp get_pull_id(url) do
    with %URI{path: "/" <> path} <- URI.parse(url),
         [owner, repo, "pull", number] <- String.split(path, "/") do
      {:ok, owner, repo, number}
    else
      _ -> {:error, "could not parse github url"}
    end
  end
end
