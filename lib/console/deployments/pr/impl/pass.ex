defmodule Console.Deployments.Pr.Impl.Pass do
  @behaviour Console.Deployments.Pr.Dispatcher

  def create(_pr, _branch, _ctx), do: {:ok, ""}
end