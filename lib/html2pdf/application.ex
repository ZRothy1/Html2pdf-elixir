defmodule Html2pdf.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Html2pdfWeb.Telemetry,
      Html2pdf.Repo,
      {DNSCluster, query: Application.get_env(:html2pdf, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Html2pdf.PubSub},
      {Oban, Application.fetch_env!(:html2pdf, Oban)},
      {DynamicSupervisor, name: Html2pdf.CrawlerSupervisor, strategy: :one_for_one},
      {ChromicPDF, chromic_pdf_opts()},
      # Start a worker by calling: Html2pdf.Worker.start_link(arg)
      # {Html2pdf.Worker, arg},
      # Start to serve requests, typically the last entry
      Html2pdfWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Html2pdf.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Set up any ChromicPDFs options such as `on_demand` using config driven architecture
  defp chromic_pdf_opts() do
    Application.get_env(:html2pdf, ChromicPDF)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Html2pdfWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
