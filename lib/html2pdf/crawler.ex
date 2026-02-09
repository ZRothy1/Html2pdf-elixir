defmodule Html2pdf.Crawler do
  @moduledoc """
  The actual crawler for a request

  The Crawler will self manage each page it crawls, spinning off tasks
  for each specific page. The tasks will then call back to this GenServer
  to queue the next batch of pages.

  The GenServer acts as the brain, deciding when and if to spin off the tasks,
  as well will report back to the ObanJob to let the LiveView know when it's
  done.
  """
  use GenServer
  require Logger

  def start_link(initial_args) do
    GenServer.start_link(__MODULE__, initial_args)
  end

  def init({url, max_depth, parent_pid}) do
    state = %{
      visited: MapSet.new(),
      active_workers: 0,
      url: url,
      max_depth: max_depth,
      parent_pid: parent_pid
    }

    # Kick off the crawl from the root directory
    send(self(), {:crawl, {url, 1}})

    {:ok, state}
  end

  # If we aren't at max depth kick off a Task to crawl a specific page and update the state.
  # Otherwise we keep the current state and wait until other messages come in.
  def handle_info({:crawl, {url, depth}}, state) do
    state =
      if depth > state.max_depth do
        state
      else
        %{
          visited: visited,
          active_workers: active_worker_count
        } = state

        visited = MapSet.put(visited, url)
        active_worker_count = active_worker_count + 1

        spawn_crawler(url, depth)

        %{state | visited: visited, active_workers: active_worker_count}
      end

    {:noreply, state}
  end

  # Handle incoming messages from our Task async workers.
  def handle_info(:completed, state) do
    worker_count = state.active_workers - 1

    state = %{state | active_workers: worker_count}

    # If we have no more workers, let's end the task so we send a message to the Oban task
    if worker_count == 0 do
      send(state.parent_pid, {:crawl_success, state.visited})

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Create an Async task that crawls a URL
  #
  # Parameters:
  #   * `url` - The URL to crawl
  #   * `depth` - The current depth of the request
  #
  # A Async task will be kicked off that fires a GET request to the URL to get the response
  # body, following any HTTP redirection requests. As long as the body is a string, we will
  # attempt to parse the it as HTML for any additional URLs to crawl. These URls are sent back
  # to the spawning GenServer.
  #
  # If the request fails, or the body is not HTML an error is logged to console.
  defp spawn_crawler(url, depth) do
    parent_pid = self()

    Task.async(fn ->
      # TODO crawl a url, and send back the info to `parent_pid`
      case Req.get(url) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          parse_body(body, parent_pid, depth, url)

        {:error, reason} ->
          Logger.error("Request to #{url} failed due to #{inspect(reason)}")

        {:ok, %{status: 200, body: _}} ->
          Logger.error("Received non-string body from #{url}")

        {:ok, %{status: status}} ->
          Logger.error("Received a #{status} response from #{url}")
      end

      # Call back to the Parent PID to show we completed our work
      send(parent_pid, :completed)
    end)
  end

  # Parse and find any anchor links within the document
  #
  # Parameters:
  # * `html_document` - A string of an HTML to parse for
  # * `parent_pid` - the PID of the GenServer to send message to for new links to crawl
  # * `parent_url` - The URL the document is for
  #
  # For each anchor tag found, grab the HREF and send a message to the GenServer for the request
  # to crawl any further pages
  defp parse_body(html_document, parent_pid, depth, url) do
    case Floki.parse_document(html_document) do
      {:ok, document} ->
        Floki.find(document, "a")
        |> Floki.attribute("href")
        |> Enum.each(fn next_url ->
          next_url =
            if String.starts_with?(next_url, "/") do
              # Handle partial URLs by constructing a full path. Include the port *just in case*
              # the URL is not on a typical port of 443 or 80
              #
              # Returns a url such as https://example.com:443/some/path
              relative_to_absolute_url(url, next_url)
            else
              next_url
            end

          send(parent_pid, {:crawl, {next_url, depth + 1}})
        end)

      {:error, reason} ->
        Logger.error("Failed to parse HTML from #{url}: #{reason}")
    end
  end

  # Construct an absolute URL from a relative path
  #
  # Parameters:
  # * `url` - the original URL the request was to
  # * `relative_url` - The relative URL (path) for an href.
  #
  # In order to accomodate non-standard ports, I also check the schema and ports.
  # If they are non-standard for HTTP or HTTPS the port is added to the URL returned. This
  # was done so that the end user is not overwhelmed with different style URLs.
  #
  # I don't think this likely will pop up, but better safe than sorry.
  #
  # Returns a complete url e.g. `https://example.com` or `https://example.com:443/path"
  defp relative_to_absolute_url(url, relative_url) do
    {:ok, %{scheme: scheme, host: host, port: port}} = URI.new(url)

    case {scheme, port} do
      {"https", 443} -> "#{scheme}://#{host}#{relative_url}"
      {"http", 80} -> "#{scheme}://#{host}#{relative_url}"
      _ -> "#{scheme}://#{host}#:#{port}{relative_url}"
    end
  end
end
