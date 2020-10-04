defmodule Watchman.Factory do
  use ExMachina.Ecto, repo: Watchman.Repo
  alias Watchman.Schema

  def build_factory do
    %Schema.Build{
      repository: sequence(:repo, &"repo-#{&1}"),
      status: :queued,
      type: :deploy,
      creator: build(:user)
    }
  end

  def command_factory do
    %Schema.Command{
      build: build(:build),
      command: "some command"
    }
  end

  def webhook_factory do
    %Schema.Webhook{
      url: sequence(:webhook, &"https://example.com/#{&1}"),
      type: :piazza,
      health: :healthy
    }
  end

  def user_factory do
    %Schema.User{
      name: "Some User",
      email: sequence(:user, &"user-#{&1}@example.com")
    }
  end

  def invite_factory do
    %Schema.Invite{
      email: sequence(:invite, &"someone-#{&1}@example.com"),
      secure_id: sequence(:invite, &"secure-#{&1}")
    }
  end

  def changelog_factory do
    %Schema.Changelog{
      repo: "repo",
      tool: sequence(:changelog, & "tool-#{&1}"),
      build: build(:build)
    }
  end
end