defmodule Console.AI.PubSub.Vector.Indexable do
  @type t :: %__MODULE__{data: any, filters: keyword | nil, delete: boolean}
  defstruct [:data, :filters, force: false, delete: false]
end
