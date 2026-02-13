defmodule Spheric.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SphericWeb.Telemetry,
      # Spheric.Repo,  # TODO: re-enable when PostgreSQL is available
      {DNSCluster, query: Application.get_env(:spheric, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Spheric.PubSub},
      Spheric.Game.WorldServer,
      SphericWeb.Presence,
      SphericWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Spheric.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SphericWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
