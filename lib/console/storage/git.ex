defmodule Console.Storage.Git do
  import Console
  import Console.Commands.Command, only: [cmd: 2, cmd: 3]
  alias Console.Commands.Plural

  def init() do
    unless File.exists?(workspace()) do
      with {:ok, _} <- cmd("git", ["clone", conf(:git_url)]),
           {:ok, _} <- git("config", ["user.name", conf(:git_user_name)]),
           {:ok, _} <- git("config", ["user.email", conf(:git_user_email)]),
        do: Plural.unlock()
    else
      pull()
    end
  end

  def push(retry \\ 0) do
    case {git("push"), retry} do
      {{:ok, _} = result, _} -> result
      {_, retries} when retries >= 3 -> {:error, :exhausted_retries}
      {_, retry} ->
        with {:ok, _} <- git("pull", ["--rebase"]),
          do: push(retry + 1)
    end
  end

  def pull() do
    with {:ok, _} <- git("reset", ["--hard", "origin/#{branch()}"]),
      do: git("pull", ["--rebase"])
  end

  def revise(msg) do
    with {:ok, _} <- git("add", ["."]),
      do: git("commit", ["-m", msg])
  end

  def revision() do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: workspace()) do
      {sha, 0} -> {:ok, sha}
      {result, _} -> {:error, result}
    end
  end

  def git(cmd, args \\ []),
    do: cmd("git", [cmd | args], workspace())

  defp branch(), do: Console.conf(:branch, "master")
end