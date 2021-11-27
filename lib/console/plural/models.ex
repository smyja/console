defmodule Console.Plural.Installation do
  defstruct [:id, :repository, :oidcProvider]
end

defmodule Console.Plural.User do
  defstruct [:id, :email]
end

defmodule Console.Plural.Group do
  defstruct [:id, :name]
end

defmodule Console.Plural.Dashboard do
  defstruct [:name, :uid]
end

defmodule Console.Plural.Repository do
  defstruct [:id, :icon, :name, :description, :dashboards]
end

defmodule Console.Plural.Recipe do
  defstruct [:id, :name, :description, :provider, :repository, :oidcSettings, :recipeSections]
end

defmodule Console.Plural.OIDCSettings do
  defstruct [:authMethod, :domainKey, :uriFormat]
end

defmodule Console.Plural.ProviderBinding do
  alias Console.Plural.{User, Group}

  defstruct [:user, :group]

  def spec() do
    %__MODULE__{
      user: %User{},
      group: %Group{}
    }
  end
end

defmodule Console.Plural.OIDCProvider do
  alias Console.Plural.{ProviderBinding}

  defstruct [:redirectUris, :bindings]

  def spec() do
    %__MODULE__{
      bindings: [ProviderBinding.spec()]
    }
  end
end

defmodule Console.Plural.RecipeSection do
  alias Console.Plural.{ConfigurationItem, RecipeItem, Repository}
  defstruct [:id, :repository, :recipeItems]

  def spec() do
    %__MODULE__{
      repository: %Repository{}
      configuration: [ConfigurationItem.spec()],
      recipe_items: [RecipeItem.spec()]
    }
  end
end

defmodule Console.Plural.RecipeItem do
  alias Console.Plural.ConfigurationItem

  defstruct [:id, :configuration]

  def spec() do
    %__MODULE__{
      configuration: [ConfigurationItem.spec()]
    }
  end
end

defmodule Console.Plural.ConfigurationItem do
  defstruct [:name, :default, :documentation, :type, :placeholder, :condition]

  def spec() do
    %__MODULE__{
      condition: %Console.Plural.Condition{}
    }
  end
end

defmodule Console.Plural.Condition do
  defstruct [:operation, :field, :value]
end

defmodule Console.Plural.Edge do
  defstruct [:node]
end

defmodule Console.Plural.PageInfo do
  defstruct [:endCursor, :hasNextPage]
end

defmodule Console.Plural.Connection do
  defstruct [:edges, :pageInfo]
end

defmodule Console.Plural.UpgradeQueue do
  defstruct [:id]
end

defmodule Console.Plural.Incident do
  defstruct [:id, :title, :description, :severity, :status]
end
