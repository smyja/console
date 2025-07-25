defmodule Console.AI.Agents.Terraform do
  use Console.AI.Agents.Base
  import Console.AI.Evidence.Base, only: [prepend: 2]
  alias Console.Schema.{StackRun, StackState, RunStep}
  alias Console.Deployments.Pr
  alias Console.AI.Tool
  alias Console.Repo

  def handle_cast({:enqueue, :booted}, {_, %AgentSession{stack_id: id} = session})
      when is_binary(id) do
    Logger.info "handling booted terraform agent, proceeding to pr generation #{session.id}"
    {thread, session} = setup_context(session)
    Tool.upsert(%{session: %{session | tf_booted: true}})
    Logger.info "context resetup for #{session.id}"
    drive(thread, [
      user_message("""
      Ok we've found the needed files, now create a pr for this to solve for:

      #{session.prompt}
      """)
    ], thread.user)
    |> handle_result(thread, session)
  end

  def handle_cast({:enqueue, %StackRun{status: :failed} = run}, {_thread, session}) do
    Logger.info("found failed terraform run in agent session #{session.id}")
    {thread, session} = setup_context(session)
    Tool.upsert(%{session: %{session | tf_planned: true, tf_booted: true}})
    case failed_run_messages(run) do
      [_ | _] = messages ->
        Logger.info("handling failed terraform run in agent session #{session.id}")
        drive(thread, messages, thread.user)
        |> handle_result(thread, session)
      _ -> {:noreply, {thread, session}}
    end
  end

  def handle_cast({:enqueue, %StackRun{} = run}, {_thread, session}) do
    Logger.info("found successful terraform run in agent session #{session.id}")
    {thread, session} = setup_context(session)
    Tool.upsert(%{session: %{session | tf_planned: true, tf_booted: true}})
    case Repo.preload(run, [:state]) do
      %StackRun{state: %StackState{plan: p}} when is_binary(p) and byte_size(p) > 0 ->
        Logger.info("handling successful terraform run in agent session #{session.id}")
        drive(thread, [
          user_message("""
          The Plural stack #{run.stack.name} has a generated a plan for the following pr, can you ensure the changes are as desired and if everything is good, feel free to ignore:

          ```terraform
          #{Pr.Utils.filter_ansi(p)}
          ```
          """)
        ], thread.user)
        |> handle_result(thread, session)
      _ -> {:noreply, {thread, session}}
    end
  end

  def handle_cast(_, state), do: {:noreply, state}

  defp failed_run_messages(%StackRun{} = run) do
    case Repo.preload(run, [steps: :logs]) do
      %StackRun{steps: [_ | _] = steps} ->
        Enum.map(steps, &step_message/1)
        |> prepend(user_message("The terraform stack plan has failed, I'll list the logs explaining the failure, and please make the necessary changes to the stack to fix the issue."))
      _ ->
        []
    end
  end

  defp step_message(%RunStep{logs: logs, cmd: cmd, args: args}) do
    logs = Enum.map(logs, & &1.logs) |> Enum.join("")
    user_message("The stack run executed the command `#{cmd} #{Enum.join(args, " ")}, with logs: #{logs}")
  end
end
