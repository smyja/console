defmodule Watchman do
  def conf(key), do: Application.get_env(:watchman, key)

  def namespace(namespace) do
    case Watchman.Forge.Config.fetch_file() do
      %{"namespacePrefix" => pref} when is_binary(pref) -> "#{pref}#{namespace}"
      _ -> namespace
    end
  end

  def workspace(), do: Path.join(conf(:workspace_root), conf(:repo_root))

  def hmac(secret, payload) do
    :crypto.hmac(:sha, secret, payload)
    |> Base.encode16(case: :lower)
  end

  def sha(body) do
    :crypto.hash(:sha, body)
    |> Base.url_encode64()
  end

  def storage, do: Watchman.Storage.Git
end
