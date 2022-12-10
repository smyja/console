defmodule Console.GraphQl.Schema do
  use Console.GraphQl.Schema.Base
  alias Console.Schema
  alias Console.Middleware.{Rbac}
  alias Console.GraphQl.Resolvers.{Build, User}

  import_types Absinthe.Plug.Types
  import_types Console.GraphQl.CustomTypes

  ## ENUMS
  ecto_enum :status, Schema.Build.Status
  ecto_enum :build_type, Schema.Build.Type

  enum :tool do
    value :helm
    value :terraform
  end

  ## INPUTS

  input_object :build_attributes do
    field :repository, non_null(:string)
    field :type,       :build_type
    field :message,    :string
  end

  input_object :invite_attributes do
    field :email, :string
  end

  ## OBJECTS
  object :build do
    field :id,           non_null(:id)
    field :repository,   non_null(:string)
    field :type,         non_null(:build_type)
    field :status,       non_null(:status)
    field :message,      :string
    field :completed_at, :datetime
    field :sha,          :string

    connection field :commands, node_type: :command do
      resolve &Build.list_commands/2
    end

    field :creator,  :user, resolve: dataloader(User)
    field :approver, :user, resolve: dataloader(User)
    field :changelogs, list_of(:changelog) do
      middleware Rbac, perm: :configure, field: :repository
      resolve dataloader(Build)
    end

    timestamps()
  end

  object :changelog do
    field :id,      non_null(:id)
    field :repo,    non_null(:string)
    field :tool,    non_null(:string)
    field :content, :string

    timestamps()
  end

  object :command do
    field :id,           non_null(:id)
    field :command,      non_null(:string)
    field :exit_code,    :integer
    field :stdout,       :string
    field :completed_at, :datetime
    field :build,        :build, resolve: dataloader(Build)

    timestamps()
  end

  object :configuration do
    field :terraform, :string
    field :helm,      :string
  end

  object :log_label do
    field :name,  :string
    field :value, :string
  end

  object :plural_manifest do
    field :network,       :manifest_network
    field :bucket_prefix, :string
    field :cluster,       :string
  end

  object :manifest_network do
    field :plural_dns, :boolean
    field :subdomain,  :string
  end

  object :git_status do
    field :cloned, :boolean
    field :output, :string
  end

  object :console_configuration do
    field :git_commit,      :string
    field :is_demo_project, :boolean

    field :manifest,        :plural_manifest, resolve: fn
      _, _, _ ->
        case Console.Plural.Manifest.get() do
          {:ok, _} = res -> res
          _ -> {:ok, %{}}
        end
    end

    field :git_status, :git_status, resolve: fn
      _, _, _ -> {:ok, Console.Bootstrapper.status()}
    end
  end

  delta :build
  delta :command

  connection node_type: :build
  connection node_type: :command
end
