defmodule Console.Services.PluralTest do
  use Console.DataCase, async: true
  use Mimic
  alias Console.Services.Plural
  alias Console.Plural.Queries

  describe "update_configuration/2" do
    @tag :skip
    test "it can update configuration in a Plural repo" do
      repo = "repo"
      expected_path = Path.join([Console.workspace(), repo, "helm", repo, "values.yaml"])
      expect(File, :write, fn ^expected_path, _ -> :ok end)

      {:ok, _} = Plural.update_configuration(repo, "updated: yaml", :helm)
    end

    @tag :skip
    test "It will fail on invalid yaml" do
      repo = "repo"
      {:error, _} = Plural.update_configuration(repo, "- key:", :helm)
    end
  end

  describe "#install_recipe/4" do
    test "a user can install a recipe" do
      get_body = Jason.encode!(%{
        query: Queries.get_recipe_query(),
        variables: %{id: "id"}
      })

      inst_body = Jason.encode!(%{
        query: Queries.install_recipe_mutation(),
        variables: %{id: "id", ctx: "{}"}
      })

      recipe = %{
        id: "id",
        name: "name",
        description: "description",
        repository: %{id: "id2", name: "repo"}
      }

      expect(HTTPoison, :post, 2, fn
        _, ^get_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{recipe: recipe}})}}
        _, ^inst_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{installRecipe: [%{id: "huh"}]}})}}
      end)

      user = insert(:user)
      {:ok, build} = Plural.install_recipe(
        "id",
        %{"repo" => %{"some" => "value"}},
        false,
        user
      )

      assert build.type == :install
      assert build.message == "Installed bundle name for repository repo"
      assert build.context == %{
        configuration: %{"repo" => %{"some" => "value"}},
        bundle: %{repository: "repo", name: "name"}
      }
      assert build.creator_id == user.id
    end

    test "a user can enable oidc after installation" do
      get_body = Jason.encode!(%{
        query: Queries.get_recipe_query(),
        variables: %{id: "id"}
      })

      inst_body = Jason.encode!(%{
        query: Queries.install_recipe_mutation(),
        variables: %{id: "id", ctx: "{}"}
      })

      me_body = Jason.encode!(%{
        query: Queries.me_query(),
        variables: %{}
      })

      get_inst_body = Jason.encode!(%{
        query: Queries.get_installation_query(),
        variables: %{name: "repo"}
      })

      oidc_body = Jason.encode!(%{
        query: Queries.upsert_oidc_provider(),
        variables: %{id: "instid", attributes: %{
          redirectUris: ["https://domain.com/oauth"],
          bindings: [%{userId: "me"}],
          authMethod: "POST"
        }}
      })

      recipe = %{
        id: "id",
        name: "name",
        description: "description",
        oidcSettings: %{authMethod: "POST", uriFormat: "https://{domain}/oauth", domainKey: "domain"},
        repository: %{id: "id2", name: "repo"}
      }

      expect(HTTPoison, :post, 5, fn
        _, ^get_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{recipe: recipe}})}}
        _, ^me_body, _ -> {:ok, %{body: Jason.encode!(%{data: %{me: %{id: "me"}}})}}
        _, ^get_inst_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{installation: %{id: "instid"}}})}}
        _, ^oidc_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{upsertOidcProvider: %{id: "id"}}})}}
        _, ^inst_body, _ ->
          {:ok, %{body: Jason.encode!(%{data: %{installRecipe: [%{id: "huh"}]}})}}
      end)

      user = insert(:user)
      {:ok, build} = Plural.install_recipe(
        "id",
        %{"repo" => %{"domain" => "domain.com"}},
        true,
        user
      )

      assert build.type == :install
      assert build.message == "Installed bundle name for repository repo"
      assert build.context == %{
        configuration: %{"repo" => %{"domain" => "domain.com"}},
        bundle: %{repository: "repo", name: "name"}
      }
      assert build.creator_id == user.id
    end
  end
end
