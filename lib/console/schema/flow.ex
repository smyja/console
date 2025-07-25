defmodule Console.Schema.Flow do
  use Piazza.Ecto.Schema
  alias Console.Schema.{Project, PolicyBinding, User, McpServerAssociation}
  alias Console.Deployments.Policies.Rbac

  schema "flows" do
    field :name,        :string
    field :description, :string
    field :icon,        :string

    field :write_policy_id, :binary_id
    field :read_policy_id,  :binary_id

    belongs_to :project, Project

    has_many :read_bindings, PolicyBinding,
      on_replace: :delete,
      foreign_key: :policy_id,
      references: :read_policy_id
    has_many :write_bindings, PolicyBinding,
      on_replace: :delete,
      foreign_key: :policy_id,
      references: :write_policy_id
    has_many :server_associations, McpServerAssociation, on_replace: :delete
    has_many :servers, through: [:server_associations, :server]

    timestamps()
  end

  def for_user(query \\ __MODULE__, %User{} = user) do
    Rbac.globally_readable(query, user, fn query, id, groups ->
      from(f in query,
        join: p in assoc(f, :project),
        left_join: b in PolicyBinding,
          on: b.policy_id == f.read_policy_id or b.policy_id == f.write_policy_id
                or b.policy_id == p.read_policy_id or b.policy_id == p.write_policy_id,
        where: b.user_id == ^id or b.group_id in ^groups,
        distinct: true
      )
    end)
  end

  def for_project(query \\ __MODULE__, project_id) do
    from(f in query, where: f.project_id == ^project_id)
  end

  def search(query \\ __MODULE__, q) do
    from(f in query, where: ilike(f.name, ^"%#{q}%"))
  end

  def stream(query \\ __MODULE__) do
    from(f in query, order_by: [asc: :id])
  end

  def ordered(query \\ __MODULE__, order \\ [asc: :name]) do
    from(f in query, order_by: ^order)
  end

  def changeset(model, attrs \\ %{}) do
    model
    |> cast(attrs, ~w(name description icon project_id)a)
    |> cast_assoc(:server_associations)
    |> cast_assoc(:read_bindings)
    |> cast_assoc(:write_bindings)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:project_id)
    |> put_new_change(:write_policy_id, &Ecto.UUID.generate/0)
    |> put_new_change(:read_policy_id, &Ecto.UUID.generate/0)
    |> validate_required([:name, :project_id])
  end

  def rbac_changeset(model, attrs \\ %{}) do
    model
    |> cast(attrs, [])
    |> cast_assoc(:read_bindings)
    |> cast_assoc(:write_bindings)
  end
end
