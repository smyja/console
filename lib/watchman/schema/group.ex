defmodule Watchman.Schema.Group do
  use Piazza.Ecto.Schema

  schema "groups" do
    field :name,        :string
    field :description, :string
    field :global,      :boolean

    timestamps()
  end

  def global(query \\ __MODULE__) do
    from(g in query, where: g.global)
  end

  @valid ~w(name description)a

  def ordered(query \\ __MODULE__, order \\ [asc: :name]) do
    from(m in query, order_by: ^order)
  end

  def changeset(model, attrs \\ %{}) do
    model
    |> cast(attrs, @valid)
    |> unique_constraint(:name)
    |> validate_required([:name])
  end
end