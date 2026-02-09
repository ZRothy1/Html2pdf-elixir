defmodule Html2pdf.CrawlJob do
  @moduledoc """
  This is an Oban Job that will be used to manage each job,
  ensuring only a max of 5 concurrent jobs are picked. In the future
  I want to look into and replace this with raw OTP as I don't actually
  need a database except for the Oban Queues.
  """
  use Oban.Worker,
    max_attempts: 1,
    queue: :crawlers,
    tags: ["crawl_requests"]

  alias Html2pdf.Crawler

  @impl Oban.Worker
  def perform(%{args: %{"uri" => uri, "depth" => depth, "job_id" => job_id}} = _job) do
    child_spec = %{
      id: Crawler,
      start: {Crawler, :start_link, [{uri, depth, self()}]},
      restart: :transient
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(Html2pdf.CrawlerSupervisor, child_spec)

    _ref = Process.monitor(pid)

    receive do
      # This isn't the most robust solution as we are passing around a potentially large
      # list of URLs in memory. A better solution for the longer term would be to save this temporarily
      # to the database, or even an ETS Table.
      {:crawl_success, urls} ->
        Phoenix.PubSub.broadcast(Html2pdf.PubSub, job_id, {:crawl_complete, urls})

        :ok

      _msg ->
        Phoenix.PubSub.broadcast(Html2pdf.PubSub, job_id, {:crawl_complete, []})

        {:cancel, "GenServer has crashed"}
    end
  end
end
