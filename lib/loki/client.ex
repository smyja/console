defmodule Loki.Client do
  alias Loki.{Response, Data, Result, Value}

  def host(), do: Application.get_env(:watchman, :loki)

  def query(query, start_ts, end_ts, limit) do
    query = URI.encode_query(%{"query" => query, "start" => start_ts, "end" => end_ts, "limit" => limit}) |> IO.inspect()

    host()
    |> Path.join("/loki/api/v1/query_range?#{query}")
    |> HTTPoison.get()
    |> case do
      {:ok, %{body: body, status_code: 200}} ->
        {:ok, body
              |> IO.inspect()
              |> Poison.decode(as: %Response{data: %Data{result: [%Result{}]}})
              |> convert()}
      error ->
        IO.inspect(error)
    end
  end

  defp convert({:ok, %Response{data: %Data{result: results}} = resp}) when is_list(results) do
    results = Enum.map(results, fn %{values: values} = result ->
      %{result | values: Enum.map(values, fn [ts, v] -> %Value{timestamp: ceil(ts * 1000), value: v} end)}
    end)
    put_in(resp.data.result, results)
  end
  defp convert(error), do: error
end