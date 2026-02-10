defmodule Html2pdf.CrawlJob do
  @moduledoc """
  This Oban Job is a longer lived process, but is lightweight. It kicks off a GenServer
  to process the crawl request and stays alive as long as that GenServer does.

  The GenServer is supervised under a DynamicSupervisor to group all crawlers under one
  supervisor process rather than each Oban Job having its own. I don't use the retry
  functionality from Supervisors and instead rely on Oban's to allow a back-off policy
  for retries.

  Once a GenServer completes its job or encounters other failures, this job will complete. On `:normal`
  shutdowns the job will complete. However on other messages from the GenServer's Process it will
  return an error and broadcast that error only on the max attempt. This way the user who was waiting
  on this job does not have to refresh to get unblocked from a new attempt.
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

    # If we shut down with a reason of `:normal` the crawler completed its task. However
    # any other reason is not considered a success as it may be a brutal kill or a crash. In this case
    # treat the job as an error. This way the task doesn't become long standing, nor blocks others from
    # being processed in cases such as a website being down.
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
