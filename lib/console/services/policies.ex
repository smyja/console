defmodule Console.Services.Policies do
  use Console.Services.Base
  use Nebulex.Caching
  alias Console.Schema.{UpgradePolicy, User}
  alias Console.PubSub

  @ttl :timer.minutes(15)

  @decorate cacheable(cache: Console.Cache, key: :upgrade_policies, opts: [ttl: @ttl])
  def upgrade_policies(), do: Console.Repo.all(UpgradePolicy)

  def get_upgrade_policy!(id), do: Console.Repo.get!(UpgradePolicy, id)

  @decorate cache_evict(cache: Console.Cache, keys: [:upgrade_policies])
  def create_upgrade_policy(attrs, %User{roles: %{admin: true}} = user) do
    %UpgradePolicy{}
    |> UpgradePolicy.changeset(attrs)
    |> Console.Repo.insert()
    |> notify(:create, user)
  end
  def create_upgrade_policy(_, _), do: {:error, :forbidden}

  @decorate cache_evict(cache: Console.Cache, keys: [:upgrade_policies])
  def delete_upgrade_policy(id, %User{roles: %{admin: true}} = user) do
    get_upgrade_policy!(id)
    |> Console.Repo.delete()
    |> notify(:delete, user)
  end
  def delete_upgrade_policy(_, _), do: {:error, :forbidden}

  def upgrade_type(repository, type \\ :deploy) do
    upgrade_policies()
    |> Enum.filter(&matches?(repository, &1.target))
    |> Enum.max_by(& &1.weight, fn -> nil end)
    |> case do
      %UpgradePolicy{type: type} -> type
      _ -> resolve_type(type)
    end
  end

  defp resolve_type(type) when type in ~w(deploy bounce approval dedicated config)a, do: type
  defp resolve_type(type) when type in ~w(deploy bounce approval dedicated config),
    do: String.to_existing_atom(type)
  defp resolve_type(_), do: :deploy

  def matches?(repository, target) do
    Regex.compile!("^#{String.replace(target, "*", ".*")}$")
    |> Regex.match?(repository)
  end

  defp notify({:ok, %UpgradePolicy{} = up}, :create, user),
    do: handle_notify(PubSub.UpgradePolicyCreated, up, actor: user)
  defp notify({:ok, %UpgradePolicy{} = up}, :delete, user),
    do: handle_notify(PubSub.UpgradePolicyDeleted, up, actor: user)
  defp notify(pass, _, _), do: pass
end
