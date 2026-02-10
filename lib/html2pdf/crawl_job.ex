defmodule Html2pdf.CrawlJob do
  @moduledoc """
  This is an Oban Job that will be used to manage each job,
  ensuring only a max of 5 concurrent jobs are picked. In the future
  I want to look into and replace this with raw OTP as I don't actually
  need a database except for the Oban Queues.
  """
  use Oban.Worker,
    max_attempts: 3,
    queue: :crawlers,
    tags: ["crawl_requests"]

  alias Html2pdf.Crawler

  @impl Oban.Worker
  def perform(%{args: %{"uri" => uri, "depth" => depth, "job_id" => job_id}} = job) do
    child_spec = %{
      id: Crawler,
      start: {Crawler, :start_link, [{uri, depth, job_id}]},
      # Avoid restarting and instead rely on Oban's retry system
      restart: :temporary
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(Html2pdf.CrawlerSupervisor, child_spec)

    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, _pid, :normal} ->
        :ok

      {:DOWN, ^ref, :process, _pid, reason} ->
        if job.max_attempts == job.attempt do
          Phoenix.PubSub.broadcast(Html2pdf.PubSub, job_id, :crawl_error)
        end

        {:error, "GenServer has crashed: #{inspect(reason)}"}
    end
  end
end
