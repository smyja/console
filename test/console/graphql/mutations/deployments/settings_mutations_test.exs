defmodule Console.GraphQl.Deployments.SettingsMutationsTest do
  use Console.DataCase, async: true

  describe "createProject" do
    test "admins can create a project" do
      {:ok, %{data: %{"createProject" => create}}} = run_query("""
        mutation Create($attrs: ProjectAttributes!) {
          createProject(attributes: $attrs) {
            id
            name
          }
        }
      """, %{"attrs" => %{"name" => "test"}}, %{current_user: admin_user()})

      assert create["id"]
      assert create["name"] == "test"
    end
  end

  describe "updateProject" do
    test "admins can update a project" do
      proj = insert(:project)
      {:ok, %{data: %{"updateProject" => update}}} = run_query("""
        mutation update($id: ID!, $attrs: ProjectAttributes!) {
          updateProject(id: $id, attributes: $attrs) {
            id
            name
          }
        }
      """, %{"attrs" => %{"name" => "test"}, "id" => proj.id}, %{current_user: admin_user()})

      assert update["id"] == proj.id
      assert update["name"] == "test"
    end
  end

  describe "deleteProject" do
    test "admins can delete a project" do
      proj = insert(:project)
      {:ok, %{data: %{"deleteProject" => deleted}}} = run_query("""
        mutation delete($id: ID!) {
          deleteProject(id: $id) {
            id
            name
          }
        }
      """, %{"id" => proj.id}, %{current_user: admin_user()})

      assert deleted["id"] == proj.id
      assert deleted["name"] == proj.name
    end
  end

  describe "dismissOnboarding" do
    test "admins can dismiss the onboarding" do
      settings = deployment_settings()
      {:ok, %{data: %{"dismissOnboarding" => dismissed}}} = run_query("""
        mutation dismissOnboarding {
          dismissOnboarding {
            onboarded
          }
        }
      """, %{}, %{current_user: admin_user()})

      assert dismissed["onboarded"]
      assert refetch(settings).onboarded
    end
  end

  describe "upsertCloudConnections" do
    test "admins can upsert a cloud connection" do
      group = insert(:group)

      {:ok, %{data: %{"upsertCloudConnection" => upserted}}} = run_query("""
        mutation upsertCloudConnection($attrs: CloudConnectionAttributes!) {
          upsertCloudConnection(attributes: $attrs) {
            id
            name
            provider
            readBindings { group { name } }
            configuration { aws { accessKeyId } }
          }
        }
      """, %{
        "attrs" => %{
          "name" => "test",
          "provider" => "AWS",
          "configuration" => %{"aws" => %{"accessKeyId" => "test", "secretAccessKey" => "test", "region" => "us-east-1"}},
          "readBindings" => [%{"groupId" => group.id}]
        }
      }, %{current_user: admin_user()})

      assert upserted["id"]
      assert upserted["name"] == "test"
      assert upserted["provider"] == "AWS"
      assert upserted["configuration"]["aws"]["accessKeyId"] == "test"

      [binding] = upserted["readBindings"]
      assert binding["group"]["name"] == group.name
    end

    test "admins can update bindings on a cloud connection" do
      group = insert(:group)
      other_group = insert(:group)
      conn = insert(:cloud_connection, provider: :aws, read_bindings: [%{group_id: group.id}])

      {:ok, %{data: %{"upsertCloudConnection" => upserted}}} = run_query("""
        mutation upsertCloudConnection($attrs: CloudConnectionAttributes!) {
          upsertCloudConnection(attributes: $attrs) {
            id
            name
            provider
            readBindings { group { name } }
            configuration { aws { accessKeyId } }
          }
        }
      """, %{
        "attrs" => %{
          "name" => conn.name,
          "provider" => "AWS",
          "configuration" => %{"aws" => %{"accessKeyId" => "test", "secretAccessKey" => "test", "region" => "us-east-1"}},
          "readBindings" => [%{"groupId" => group.id}, %{"groupId" => other_group.id}]
        }
      }, %{current_user: admin_user()})

      assert upserted["id"] == conn.id
      assert upserted["name"] == conn.name
      assert upserted["provider"] == "AWS"
      assert upserted["configuration"]["aws"]["accessKeyId"] == "test"

      bindings = upserted["readBindings"]
      assert MapSet.new(bindings, & &1["group"]["name"])
             |> MapSet.equal?(MapSet.new([group.name, other_group.name]))
    end

    test "nonadmins cannot upsert a cloud connection" do
      {:ok, %{errors: [_ | _]}} = run_query("""
        mutation upsertCloudConnection($attrs: CloudConnectionAttributes!) {
          upsertCloudConnection(attributes: $attrs) {
            id
          }
        }
      """, %{
        "attrs" => %{
          "name" => "test",
          "provider" => "AWS",
          "configuration" => %{"aws" => %{"accessKeyId" => "test", "secretAccessKey" => "test", "region" => "us-east-1"}},
        }
      }, %{current_user: insert(:user)})
    end
  end

  describe "deleteCloudConnection" do
    test "admins can delete a cloud connection" do
      conn = insert(:cloud_connection)

      {:ok, %{data: %{"deleteCloudConnection" => deleted}}} = run_query("""
        mutation deleteCloudConnection($id: ID!) {
          deleteCloudConnection(id: $id) {
            id
          }
        }
      """, %{"id" => conn.id}, %{current_user: admin_user()})

      assert deleted["id"] == conn.id
      refute refetch(conn)
    end

    test "nonadmins cannot delete a cloud connection" do
      conn = insert(:cloud_connection)

      {:ok, %{errors: [_ | _]}} = run_query("""
        mutation deleteCloudConnection($id: ID!) {
          deleteCloudConnection(id: $id) {
            id
          }
        }
      """, %{"id" => conn.id}, %{current_user: insert(:user)})
    end
  end

  describe "createFederatedCredential" do
    test "admins can create a federated credential" do
      user = insert(:user)
      {:ok, %{data: %{"createFederatedCredential" => created}}} = run_query("""
        mutation createFederatedCredential($attrs: FederatedCredentialAttributes!) {
          createFederatedCredential(attributes: $attrs) {
            id
            issuer
            claimsLike
            scopes
            user { id }
          }
        }
      """, %{"attrs" => %{
        "issuer" => "https://oidc.plural.sh",
        "claimsLike" => Jason.encode!(%{"sub" => ".*@plural.sh"}),
        "scopes" => ["createPullRequest"],
        "user_id" => user.id
      }}, %{current_user: admin_user()})

      assert created["id"]
      assert created["issuer"] == "https://oidc.plural.sh"
      assert created["claimsLike"] == %{"sub" => ".*@plural.sh"}
      assert created["scopes"] == ["createPullRequest"]
      assert created["user"]["id"] == user.id
    end
  end

  describe "updateFederatedCredential" do
    test "admins can update a federated credential" do
      credential = insert(:federated_credential)
      user = insert(:user)
      {:ok, %{data: %{"updateFederatedCredential" => updated}}} = run_query("""
        mutation updateFederatedCredential($id: ID!, $attrs: FederatedCredentialAttributes!) {
          updateFederatedCredential(id: $id, attributes: $attrs) {
            id
            issuer
            claimsLike
            scopes
            user { id }
          }
        }
      """, %{
        "id" => credential.id,
        "attrs" => %{
          "issuer" => "https://oidc.plural.sh",
          "claimsLike" => Jason.encode!(%{"sub" => ".*@plural.sh"}),
          "scopes" => ["createPullRequest"],
          "user_id" => user.id
        }
      }, %{current_user: admin_user()})

      assert updated["id"] == credential.id
      assert updated["issuer"] == "https://oidc.plural.sh"
      assert updated["claimsLike"] == %{"sub" => ".*@plural.sh"}
      assert updated["scopes"] == ["createPullRequest"]
      assert updated["user"]["id"] == user.id
    end
  end

  describe "deleteFederatedCredential" do
    test "admins can delete a federated credential" do
      credential = insert(:federated_credential)
      {:ok, %{data: %{"deleteFederatedCredential" => deleted}}} = run_query("""
        mutation deleteFederatedCredential($id: ID!) {
          deleteFederatedCredential(id: $id) {
            id
          }
        }
      """, %{"id" => credential.id}, %{current_user: admin_user()})

      assert deleted["id"] == credential.id
      refute refetch(credential)
    end
  end
end
