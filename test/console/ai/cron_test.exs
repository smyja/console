defmodule Console.AI.CronTest do
  use Console.DataCase, async: false
  use Mimic
  import KubernetesScaffolds
  alias Console.PubSub
  alias Console.Deployments.Clusters
  alias Console.AI.Cron

  setup :set_mimic_global

  describe "#trim_threads/0" do
    test "it will trim threads for users with more than 50" do
      user = insert(:user)
      keep = insert_list(52, :chat_thread, user: user)
      drop = insert_list(3, :chat_thread, user: user, inserted_at: Timex.now() |> Timex.shift(days: -2))
      drop2 = insert_list(2, :chat_thread, last_message_at: Timex.now() |> Timex.shift(days: -30))

      keep2 = insert_list(3, :chat_thread, user: insert(:user), inserted_at: Timex.now() |> Timex.shift(days: -2))

      Cron.trim_threads()

      for t <- keep ++ keep2,
        do: assert refetch(t)

      for t <- drop ++ drop2,
        do: refute refetch(t)
    end
  end

  describe "#services/0" do
    test "it will gather info from all service components and generate" do
      deployment_settings(ai: %{enabled: true, provider: :openai, openai: %{access_token: "key"}})
      service = insert(:service, status: :failed, errors: [%{source: "manifests", error: "some error"}])
      insert(:service_component,
        service: service,
        state: :pending,
        group: "cert-manager.io",
        version: "v1",
        kind: "Certificate",
        namespace: "ns",
        name: "name"
      )
      expect(Clusters, :control_plane, fn _ -> %Kazan.Server{} end)
      expect(Kube.Client, :get_certificate, fn _, _ -> {:ok, certificate("ns")} end)
      expect(Kube.Utils, :run, fn _ -> {:ok, %{items: []}} end)
      expect(Console.AI.OpenAI, :completion, 4, fn _, _ -> {:ok, "openai completion"} end)

      Cron.services()

      %{id: id} = svc = Console.Repo.preload(refetch(service), [:insight, components: :insight])

      assert svc.insight.text

      %{components: [component]} = svc

      assert component.insight.text

      assert_receive {:event, %PubSub.ServiceInsight{item: {%{id: ^id}, _}}}
    end

    test "it will call aws bedrock correctly" do
      deployment_settings(ai: %{enabled: true, provider: :bedrock, bedrock: %{model_id: "test"}})
      service = insert(:service, status: :failed, errors: [%{source: "manifests", error: "some error"}])
      insert(:service_component,
        service: service,
        state: :pending,
        group: "cert-manager.io",
        version: "v1",
        kind: "Certificate",
        namespace: "ns",
        name: "name"
      )
      expect(Clusters, :control_plane, fn _ -> %Kazan.Server{} end)
      expect(Kube.Client, :get_certificate, fn _, _ -> {:ok, certificate("ns")} end)
      expect(Kube.Utils, :run, fn _ -> {:ok, %{items: []}} end)
      expect(ExAws, :request, 4, fn
        %ExAws.Operation.JSON{
          data: %{
            system: [%{text: _}],
            messages: [%{role: :user, content: [%{text: _}]} | _]
          }
        }, _ ->
        {:ok, %{"output" => %{"message" => %{"content" => [%{"text" => "bedrock completion"}]}}}}
      end)

      Cron.services()

      %{id: id} = svc = Console.Repo.preload(refetch(service), [:insight, components: :insight])

      assert svc.insight.text

      %{components: [component]} = svc

      assert component.insight.text

      assert_receive {:event, %PubSub.ServiceInsight{item: {%{id: ^id}, _}}}
    end

    test "it will preserve prior insight ids" do
      insight = insert(:ai_insight, updated_at: Timex.now() |> Timex.shift(days: -1))
      deployment_settings(ai: %{enabled: true, provider: :openai, openai: %{access_token: "key"}})
      service = insert(:service, insight: insight, status: :failed, errors: [%{source: "manifests", error: "some error"}])
      insert(:service_component,
        service: service,
        state: :pending,
        group: "cert-manager.io",
        version: "v1",
        kind: "Certificate",
        namespace: "ns",
        name: "name"
      )
      expect(Clusters, :control_plane, fn _ -> %Kazan.Server{} end)
      expect(Kube.Client, :get_certificate, fn _, _ -> {:ok, certificate("ns")} end)
      expect(Kube.Utils, :run, fn _ -> {:ok, %{items: []}} end)
      expect(Console.AI.OpenAI, :completion, 4, fn _, _ -> {:ok, "openai completion"} end)

      Cron.services()

      svc = Console.Repo.preload(refetch(service), [:insight, components: :insight])

      assert svc.insight.text
      assert svc.insight_id == insight.id
    end
  end

  describe "#clusters/0" do
    test "it will generate insights for failing components" do
      deployment_settings(ai: %{enabled: true, provider: :openai, openai: %{access_token: "key"}})
      cluster = insert(:cluster)
      insert(:cluster_insight_component,
        cluster: cluster,
        group: "cert-manager.io",
        version: "v1",
        kind: "Certificate",
        namespace: "ns",
        name: "name"
      )
      expect(Clusters, :control_plane, fn _ -> %Kazan.Server{} end)
      expect(Kube.Client, :get_certificate, fn _, _ -> {:ok, certificate("ns")} end)
      expect(Kube.Utils, :run, fn _ -> {:ok, %{items: []}} end)
      expect(Console.AI.OpenAI, :completion, 4, fn _, _ -> {:ok, "openai completion"} end)

      Cron.clusters()

      %{id: id} = cluster = Console.Repo.preload(refetch(cluster), [:insight, insight_components: :insight])

      assert cluster.insight.text

      %{insight_components: [component]} = cluster

      assert component.insight.text

      assert_receive {:event, %PubSub.ClusterInsight{item: {%{id: ^id}, _}}}
    end
  end

  describe "#stacks/0" do
    test "it will gather info from stack runs and generate" do
      deployment_settings(ai: %{enabled: true, provider: :openai, openai: %{access_token: "key"}})
      git = insert(:git_repository, url: "https://github.com/pluralsh/console.git")
      stack = insert(:stack, status: :failed, repository: git)
      insert(:stack_run, stack: stack)
      run   = insert(:stack_run, status: :failed, stack: stack, repository: git, git: %{ref: "master", folder: "plural/terraform/aws"})
      step  = insert(:run_step, status: :failed, cmd: "echo", args: ["hello", "work"])
      insert(:run_log, step: step, logs: "blah blah blah")
      expect(Console.AI.OpenAI, :completion, 4, fn _, _ -> {:ok, "openai completion"} end)

      Cron.stacks()

      %{id: id} = stack = Console.Repo.preload(refetch(stack), [:insight])

      assert stack.insight.text

      run = Console.Repo.preload(refetch(run), [:insight])

      assert run.insight.text

      assert_receive {:event, %PubSub.StackInsight{item: {%{id: ^id}, _}}}
    end
  end
end