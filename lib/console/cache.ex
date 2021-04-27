defmodule Console.Cache do
  use Nebulex.Cache,
    otp_app: :console,
    adapter: Nebulex.Adapters.Partitioned,
    primary_storage_adapter: Nebulex.Adapters.Local
end

defmodule Console.ReplicatedCache do
  use Nebulex.Cache,
    otp_app: :console,
    adapter: Nebulex.Adapters.Replicated
end