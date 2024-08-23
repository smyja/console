defmodule Console.GraphQl.Deployments.GitMutationsTest do
  use Console.DataCase, async: true
  use Mimic

  describe "createGitRepository" do
    test "it will create a new git repo" do
      {:ok, %{data: %{"createGitRepository" => git}}} = run_query("""
        mutation Create($attrs: GitAttributes!) {
          createGitRepository(attributes: $attrs) {
            id
            url
          }
        }
      """, %{"attrs" => %{"url" => "https://github.com/pluralsh/console.git"}}, %{current_user: admin_user()})

      assert git["url"] == "https://github.com/pluralsh/console.git"
    end
  end

  describe "updateGitRepository" do
    test "it will update a new git repo" do
      git = insert(:git_repository)

      {:ok, %{data: %{"updateGitRepository" => updated}}} = run_query("""
        mutation Create($id: ID!, $attrs: GitAttributes!) {
          updateGitRepository(id: $id, attributes: $attrs) {
            id
            url
          }
        }
      """, %{
        "id" => git.id,
        "attrs" => %{"url" => "https://github.com/pluralsh/console.git"}
      }, %{current_user: admin_user()})

      assert updated["url"] == "https://github.com/pluralsh/console.git"
    end
  end

  describe "deleteGitRepository" do
    test "it will delete a new git repo" do
      git = insert(:git_repository)

      {:ok, %{data: %{"deleteGitRepository" => del}}} = run_query("""
        mutation Delete($id: ID!) {
          deleteGitRepository(id: $id) {
            id
          }
        }
      """, %{"id" => git.id}, %{current_user: admin_user()})

      assert del["id"] == git.id
      refute refetch(git)
    end
  end

  describe "upsertHelmRepository" do
    test "it can upsert a helm repository" do
      {:ok, %{data: %{"upsertHelmRepository" => helm}}} = run_query("""
        mutation Upsert($url: String!, $attributes: HelmRepositoryAttributes!) {
          upsertHelmRepository(url: $url, attributes: $attributes) {
            id
            url
          }
        }
      """, %{
        "url" => "https://example.helm.sh",
        "attributes" => %{
          "provider" => "BEARER",
          "auth" => %{"bearer" => %{"token" => "example"}}
        }
      }, %{current_user: admin_user()})

      assert helm["url"] == "https://example.helm.sh"
    end
  end

  describe "createScmConnection" do
    test "it will create a new scm connection" do
      expect(Tentacat.Organizations.Hooks, :create, fn _, _, _ -> {:ok, %{"id" => "id"}, :ok} end)
      {:ok, %{data: %{"createScmConnection" => scm}}} = run_query("""
        mutation Create($attrs: ScmConnectionAttributes!) {
          createScmConnection(attributes: $attrs) {
            id
            type
            name
          }
        }
      """, %{"attrs" => %{
        "type" => "GITHUB",
        "name" => "test",
        "owner" => "pluralsh",
        "token" => "my-pat"
      }}, %{current_user: admin_user()})

      assert scm["type"] == "GITHUB"
      assert scm["name"] == "test"
    end
  end

  describe "updateScmConnection" do
    test "it will create a new scm connection" do
      conn = insert(:scm_connection)
      {:ok, %{data: %{"updateScmConnection" => scm}}} = run_query("""
        mutation Create($id: ID!, $attrs: ScmConnectionAttributes!) {
          updateScmConnection(id: $id, attributes: $attrs) {
            id
            type
            name
          }
        }
      """, %{"attrs" => %{
        "type" => "GITHUB",
        "name" => "test",
        "token" => "my-pat"
      }, "id" => conn.id}, %{current_user: admin_user()})

      assert scm["id"] == conn.id
      assert scm["type"] == "GITHUB"
      assert scm["name"] == "test"
    end
  end

  describe "deleteScmConnection" do
    test "it will create a new scm connection" do
      conn = insert(:scm_connection)
      {:ok, %{data: %{"deleteScmConnection" => scm}}} = run_query("""
        mutation Create($id: ID!) {
          deleteScmConnection(id: $id) {
            id
            type
            name
          }
        }
      """, %{"id" => conn.id}, %{current_user: admin_user()})

      assert scm["id"] == conn.id
      refute refetch(conn)
    end
  end

  describe "createPrAutomation" do
    test "it will create a new scm connection" do
      conn = insert(:scm_connection)
      {:ok, %{data: %{"createPrAutomation" => pr}}} = run_query("""
        mutation Create($attrs: PrAutomationAttributes!) {
          createPrAutomation(attributes: $attrs) {
            id
            name
            message
            connection { id }
          }
        }
      """, %{"attrs" => %{
        "title" => "pr title",
        "name" => "test",
        "message" => "some pr message",
        "connectionId" => conn.id,
      }}, %{current_user: admin_user()})

      assert pr["name"] == "test"
      assert pr["message"] == "some pr message"
      assert pr["connection"]["id"] == conn.id
    end
  end

  describe "updatePrAutomation" do
    test "it will create a new scm connection" do
      pr = insert(:pr_automation)
      {:ok, %{data: %{"updatePrAutomation" => updated}}} = run_query("""
        mutation Create($id: ID!, $attrs: PrAutomationAttributes!) {
          updatePrAutomation(id: $id, attributes: $attrs) {
            id
            name
          }
        }
      """, %{"attrs" => %{"name" => "test"}, "id" => pr.id}, %{current_user: admin_user()})

      assert updated["id"] == pr.id
      assert updated["name"] == "test"
    end
  end

  describe "deletePrAutomation" do
    test "it will create a new scm connection" do
      pr = insert(:pr_automation)
      {:ok, %{data: %{"deletePrAutomation" => deleted}}} = run_query("""
        mutation Create($id: ID!) {
          deletePrAutomation(id: $id) {
            id
            name
          }
        }
      """, %{"id" => pr.id}, %{current_user: admin_user()})

      assert deleted["id"] == pr.id
      refute refetch(pr)
    end
  end

  describe "createPullRequest" do
    test "it can create a new pull request given a pr automation id and arguments" do
      user = insert(:user)
      conn = insert(:scm_connection, token: "some-pat")
      pra = insert(:pr_automation, identifier: "pluralsh/console", cluster: build(:cluster), connection: conn, create_bindings: [%{user_id: user.id}])
      expect(Console.Commands.Plural, :template, fn f, _, _ -> File.read(f) end)
      expect(Tentacat.Pulls, :create, fn _, "pluralsh", "console", %{head: "pr-test"} ->
        {:ok, %{"html_url" => "https://github.com/pr/url"}, %HTTPoison.Response{}}
      end)
      expect(Console.Deployments.Pr.Git, :setup, fn conn, "pluralsh/console", "pr-test" -> {:ok, conn} end)
      expect(Console.Deployments.Pr.Git, :commit, fn _, _ -> {:ok, ""} end)
      expect(Console.Deployments.Pr.Git, :push, fn _, "pr-test" -> {:ok, ""} end)

      {:ok, %{data: %{"createPullRequest" => pr}}} = run_query("""
        mutation Create($id: ID!, $ctx: Json!, $branch: String!) {
          createPullRequest(id: $id, branch: $branch, context: $ctx) {
            id
            url
            title
          }
        }
      """, %{"id" => pra.id, "branch" => "pr-test", "ctx" => "{}"}, %{current_user: user})

      assert pr["url"] == "https://github.com/pr/url"
      assert pr["title"] == pra.title
    end
  end

  describe "createPullRequestPointer" do
    test "creates a pointer to a pull request in an external scm" do
      {:ok, %{data: %{"createPullRequestPointer" => pr}}} = run_query("""
        mutation Create($attrs: PullRequestAttributes!) {
          createPullRequestPointer(attributes: $attrs) {
            url
          }
        }
      """, %{"attrs" => %{"url" => "https://github.com/some/repo", "title" => "pr"}}, %{current_user: admin_user()})

      assert pr["url"] == "https://github.com/some/repo"
    end
  end

  describe "updatePullRequest" do
    test "it will update an existing pr" do
      pr = insert(:pull_request)

      {:ok, %{data: %{"updatePullRequest" => updated}}} = run_query("""
        mutation Update($id: ID!, $attrs: PullRequestUpdateAttributes!) {
          updatePullRequest(id: $id, attributes: $attrs) {
            id
            status
            title
          }
        }
      """, %{"id" => pr.id, "attrs" => %{"status" => "MERGED", "title" => "new title"}}, %{current_user: admin_user()})

      assert updated["id"] == pr.id
      assert updated["status"] == "MERGED"
      assert updated["title"] == "new title"
    end
  end

  describe "deletePullRequest" do
    test "it will update an existing pr" do
      pr = insert(:pull_request)

      {:ok, %{data: %{"deletePullRequest" => deleted}}} = run_query("""
        mutation Update($id: ID!) {
          deletePullRequest(id: $id) { id }
        }
      """, %{"id" => pr.id}, %{current_user: admin_user()})

      assert deleted["id"] == pr.id
      refute refetch(pr)
    end
  end

  describe "createScmWebhookPointer" do
    test "admins can create webhook pointers" do
      {:ok, %{data: %{"createScmWebhookPointer" => hook}}} = run_query("""
        mutation Create($attrs: ScmWebhookAttributes!) {
          createScmWebhookPointer(attributes: $attrs) {
            type
            url
          }
        }
      """, %{
        "attrs" => %{
          "owner" => "pluralsh",
          "hmac" => "super secret",
          "type" => "GITHUB"
        }
      }, %{current_user: admin_user()})

      assert hook["url"]
      assert hook["type"] == "GITHUB"
    end

    test "nonadmins cannot create webhook pointers" do
      {:ok, %{errors: [_ | _]}} = run_query("""
        mutation Create($attrs: ScmWebhookAttributes!) {
          createScmWebhookPointer(attributes: $attrs) {
            type
            url
          }
        }
      """, %{
        "attrs" => %{
          "owner" => "pluralsh",
          "hmac" => "super secret",
          "type" => "GITHUB"
        }
      }, %{current_user: insert(:user)})
    end
  end

  describe "deleteScmWebhook" do
    test "admins can delete scm webhooks" do
      admin = admin_user()
      hook = insert(:scm_webhook)

      {:ok, %{data: %{"deleteScmWebhook" => deleted}}} = run_query("""
        mutation Delete($id: ID!) {
          deleteScmWebhook(id: $id) {
            id
          }
        }
      """, %{"id" => hook.id}, %{current_user: admin})

      assert deleted["id"] == hook.id
      refute refetch(hook)
    end

    test "non-admins cannot delete" do
      hook = insert(:scm_webhook)

      {:ok, %{errors: [_ | _]}} = run_query("""
        mutation Delete($id: ID!) {
          deleteScmWebhook(id: $id) {
            id
          }
        }
      """, %{"id" => hook.id}, %{current_user: insert(:user)})
    end
  end
end
