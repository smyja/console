defmodule Console.AI.Graph.IndexableItem do
  @moduledoc """
  A module that defines the behaviour for indexable items.
  """
  alias Console.AI.Tools.Utils

  @type t :: %__MODULE__{
    provider: atom | binary,
    id: binary,
    type: binary,
    links: [binary],
    document: binary,
    attributes: map()
  }

  @derive Jason.Encoder
  defstruct [:id, :type, :links, :document, :attributes, :provider]

  def from_search(hit) do
    %__MODULE__{
      id: hit["_id"],
      type: hit["type"],
      links: hit["links"],
      attributes: hit["attributes"],
      provider: hit["provider"]
    }
  end

  def with_doc(%__MODULE__{} = item), do: %__MODULE__{item | document: doc(item)}

  defp doc(%__MODULE__{} = item) do
    """
    #{item.provider} #{item.type} with id #{item.id} and attributes:

    #{maybe_yaml(item.attributes)}
    """
  end

  defp maybe_yaml(val) do
    case Utils.yaml_encode(val) do
      {:ok, yaml} -> "```yaml\n#{yaml}\n```"
      {:error, _} -> "```json\n#{Jason.encode!(val)}\n```"
    end
  end
end
