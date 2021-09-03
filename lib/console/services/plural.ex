defmodule Console.Services.Plural do
  alias Console.Schema.{User, Manifest}
  alias Console.Services.{Builds}
  alias Console.Plural.{Repositories, Users, Recipe}

  def terraform_file(repository) do
    terraform_filename(repository)
    |> File.read()
  end

  def values_file(repository) do
    vals_filename(repository)
    |> File.read()
  end

  def update_configuration(repository, update, tool) do
    with {:ok, _} <- validate(update, tool),
         :ok <- File.write(filename(repository, tool), update),
      do: {:ok, update}
  end

  def install_recipe(id, context, oidc, %User{} = user) do
    with {:ok, recipe} <- Repositories.get_recipe(id),
         {:ok, _} <- Repositories.install_recipe(id),
         :ok <- configure_oidc(recipe, context, oidc) do
      Builds.create(%{
        type: :install,
        repository: recipe.repository.name,
        message: "Installed bundle #{recipe.name} for repository #{recipe.repository.name}",
        context: %{
          configuration: context,
          bundle: %{repository: recipe.repository.name, name: recipe.name},
        },
      }, user)
    end
  end

  def configure_oidc(
    %Recipe{
      repository: %{name: name},
      oidcSettings: %{authMethod: method, uriFormat: fmt, domainKey: key}
    },
    context,
    true) do
    with {:ok, %{id: me}} <- Users.me(),
         {:ok, %{id: inst_id}} <- Repositories.get_installation(name),
         {:ok, _} <- Repositories.upsert_oidc_provider(inst_id, %{
           redirectUris: [String.replace(fmt, "{domain}", get_in(context, [name, key]))],
           authMethod: method,
           bindings: [%{userId: me}]
         }),
      do: :ok
  end
  def configure_oidc(_, _, _), do: :ok

  def cluster_name() do
    case project_manifest() do
      {:ok, %Manifest{cluster: cluster}} -> cluster
      _ -> ""
    end
  end

  def project_manifest() do
    manifest_filename()
    |> YamlElixir.read_from_file()
    |> case do
      {:ok, %{
        "kind" => "ProjectManifest",
        "metadata" => %{"name" => name},
        "spec" => conf
      }} -> {:ok, Manifest.build(name, conf)}
      _  -> {:error, :not_found}
    end
  end

  def filename(repo, :helm), do: vals_filename(repo)
  def filename(repo, :terraform), do: terraform_filename(repo)

  def validate(str, :helm), do: YamlElixir.read_from_string(str)
  def validate(_, _), do: {:ok, nil}

  defp vals_filename(repository) do
    Path.join([Console.workspace(), repository, "helm", repository, "values.yaml"])
  end

  defp terraform_filename(repository) do
    Path.join([Console.workspace(), repository, "terraform", "main.tf"])
  end

  defp manifest_filename(),
    do: Path.join([Console.workspace(), "workspace.yaml"])
end
