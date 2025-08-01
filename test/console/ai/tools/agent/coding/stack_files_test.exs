defmodule Console.AI.Tools.Agent.Coding.StackFilesTest do
  use Console.DataCase, async: false
  alias Console.AI.Tools.Agent.Coding.StackFiles

  describe "implement/1" do
    test "it can fetch stack files" do
      git = insert(:git_repository, url: "https://github.com/pluralsh/scaffolds.git")
      stack = insert(:stack, repository: git, git: %{ref: "main", folder: "catalogs/data/airbyte/terraform/aws"})
      run = insert(:stack_run, status: :successful, stack: stack, git: %{ref: "main", folder: "catalogs/data/airbyte/terraform/aws"})

      actor = admin_user()
      session = insert(:agent_session)
      Console.AI.Tool.context(user: actor, session: session, thread: session.thread)

      {:ok, result} = StackFiles.implement(%StackFiles{stack_id: run.stack_id})

      assert is_binary(result)

      assert refetch(session).stack_id == run.stack_id
    end
  end
end
