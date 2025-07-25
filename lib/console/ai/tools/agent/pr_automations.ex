defmodule Console.AI.Tools.Agent.PrAutomations do
  use Console.AI.Tools.Agent.Base
  alias Console.Repo
  alias Console.Schema.PrAutomation

  embedded_schema do
    field :catalog, :string
  end

  @valid ~w(catalog)a

  def changeset(model, attrs) do
    model
    |> cast(attrs, @valid)
    |> validate_required([:catalog])
  end

  @fields ~w(id name description title configuration)a
  @json_schema Console.priv_file!("tools/agent/pr_automations.json") |> Jason.decode!()

  def json_schema(), do: @json_schema
  def name(), do: plrl_tool("pr_automations")
  def description(), do: "Returns a list of pr automations that are present in this catalog.  These are individual PRs that provision infrastructure a user might want to create in a tested, gitops fashion."

  def implement(%__MODULE__{catalog: catalog}) do
    PrAutomation.for_catalog_name(catalog)
    |> Repo.all()
    |> Enum.map(fn pra ->
      Map.take(pra, @fields)
      |> Console.mapify()
    end)
    |> Jason.encode()
  end
end
