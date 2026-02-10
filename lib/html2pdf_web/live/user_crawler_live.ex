defmodule Html2pdfWeb.UserCrawlerLive do
  use Html2pdfWeb, :live_view

  alias Html2pdf.CrawlJob
  alias Html2pdf.PdfGenerator

  # Maximum URLs to display per page with infinite pagination
  @urls_per_page 50
  @max_depth Application.compile_env(:html2pdf, :max_depth)

  defmodule UserForm do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    @max_depth Application.compile_env(:html2pdf, :max_depth)

    embedded_schema do
      field :uri, :string
      field :depth, :integer
    end

    @allowed ~w(uri depth)a
    # Pull max depth from a config to make it easier to configure, and use across
    # the app where necessary.

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, @allowed)
      |> validate_required(@allowed)
      |> validate_uri()
      |> validate_number(:depth, greater_than: 0, less_than_or_equal_to: @max_depth)
    end

    defp validate_uri(cs) do
      uri = get_change(cs, :uri)

      case uri && URI.new(uri) do
        {:ok, %{scheme: schema, host: "" <> _ = host}} when schema in ~w(http https) ->
          case host |> to_charlist() |> :inet.gethostbyname() do
            {:ok, _} -> cs
            {:error, _} -> add_error(cs, :uri, "Please enter a valid URL")
          end

        _ ->
          add_error(cs, :uri, "Please enter a valid URL")
      end
    end
  end

  def mount(_params, _session, socket) do
    assigns = %{
      ui: %{
        page: 1,
        end_of_timeline?: false,
        # Enum of :not_started, :queued, :in_progress, :complete
        crawl_status: :not_started,
        form: UserForm.changeset(%{}) |> to_form(),
        all_selected: false,
        is_generating_pdf?: false
      },
      data: %{
        selected_urls: MapSet.new(),
        crawled_urls: [],
        crawl_job_id: nil,
        pdf_job_id: nil
      }
    }

    socket =
      socket
      |> assign(assigns)
      |> stream(:urls, [], limit: @urls_per_page)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <div class="max-w-3/4">
        <p>
          Welcome to PDF-ify where we take a website and make it into a PDF so you can read it on the go!
        </p>

        <p>
          Enter a URL and a depth below. From there we will dig through the website and the linked pages
          up to the depth you specified. All pages will be added to the PDF
        </p>
      </div>
      <.form for={@ui.form} phx-change="validate" phx-submit="start-crawl" class="max-w-1/4">
        <.input
          field={@ui.form[:uri]}
          prompt="Enter a URL to convert to a PDF"
          phx-debounce="500"
        />
        <p>Select a max depth to crawl</p>
        <.input
          field={@ui.form[:depth]}
          type="number"
          min={1}
          max={get_max_depth()}
          phx-debounce="500"
        />
        <.button type="submit" disabled={@ui.crawl_status not in ~w(not_started completed)a}>
          Start Crawl
        </.button>
      </.form>

      <div :if={@ui.crawl_status == :queued}>
        <p>Your request is currently in queue</p>
      </div>

      <div :if={@ui.crawl_status == :in_progress}>
        <p>We are actively crawling the website, this may take a while</p>
        <%!-- TODO Write how many URIs we have so far --%>
      </div>

      <div :if={@ui.crawl_status == :completed} class="max-w-3/4">
        <p>Select the URLs you want to include in the PDF and click the button to generate it</p>
        <p>Once generated you can click the button again to download it</p>
        <div>
          <table>
            <thead>
              <tr>
                <th>
                  <.input
                    type="checkbox"
                    name="select-all"
                    phx-click="select-all"
                    label="Select All"
                    checked={@ui.all_selected}
                  />
                </th>
                <th>URL</th>
                <th>
                  <.button
                    :if={@data.pdf_job_id == nil}
                    phx-click="generate-pdf"
                    disabled={Enum.empty?(@data.selected_urls) || @ui.is_generating_pdf?}
                  >
                    <%= if @ui.is_generating_pdf? do %>
                      Generating PDF...
                    <% else %>
                      Generate PDF
                    <% end %>
                  </.button>

                  <.button
                    :if={@data.pdf_job_id != nil}
                    href={~p"/download/#{@data.pdf_job_id}"}
                    target="_blank"
                    phx-click="download-pdf"
                  >
                    Download PDF
                  </.button>
                </th>
              </tr>
            </thead>
            <tbody
              id="url-table-body"
              phx-update="stream"
              class="max-h-1/2 overflow-scroll"
              phx-viewport-top={@ui.page >= 1 && JS.push("prev-page", page_loading: true)}
              phx-viewport-bottom={!@ui.end_of_timeline? && JS.push("next-page", page_loading: true)}
            >
              <tr :for={{id, %{url: uri}} <- @streams.urls} id={id}>
                <td>
                  <.input
                    id={"#{id}-select"}
                    type="checkbox"
                    name={"#{id}-select"}
                    checked={MapSet.member?(@data.selected_urls, uri)}
                    phx-click="select-uri"
                    phx-value-uri={uri}
                  />
                </td>
                <td class="pl-4"><a href={uri} target="_blank">{uri}</a></td>
                <td></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  # Validate that the parameters are correct, and if they aren't update the form so
  # errors display.
  def handle_event("validate", %{"user_form" => params}, socket) do
    form = UserForm.changeset(params) |> to_form(action: :validate)
    ui = %{socket.assigns.ui | form: form}

    {:noreply, assign(socket, :ui, ui)}
  end

  # Kick off a crawl if it's valid
  def handle_event("start-crawl", %{"user_form" => params}, socket) do
    case UserForm.changeset(params) |> Ecto.Changeset.apply_action(:validate) do
      {:ok, %{uri: uri, depth: depth}} ->
        job_id = TypeID.new("crawl") |> TypeID.to_string()

        CrawlJob.new(%{job_id: job_id, uri: uri, depth: depth})
        |> Oban.insert()

        Phoenix.PubSub.subscribe(Html2pdf.PubSub, job_id)

        ui = %{socket.assigns.ui | crawl_status: :in_progress}

        data = %{
          socket.assigns.data
          | crawl_job_id: job_id,
            pdf_job_id: nil,
            selected_urls: MapSet.new()
        }

        {:noreply, assign(socket, %{ui: ui, data: data})}

      {:error, cs} ->
        form = to_form(cs, action: :validate)
        ui = %{socket.assigns.ui | form: form}

        {:noreply, assign(socket, :ui, ui)}
    end
  end

  # Select all event
  def handle_event("select-all", _params, socket) do
    ui = socket.assigns.ui

    {data, ui} =
      if ui.all_selected do
        ui = %{socket.assigns.ui | all_selected: false}
        data = socket.assigns.data
        data = %{data | selected_urls: MapSet.new()}

        {data, ui}
      else
        ui = %{socket.assigns.ui | all_selected: true}
        data = socket.assigns.data
        data = %{data | selected_urls: data.crawled_urls}

        {data, ui}
      end

    visible_urls =
      data.crawled_urls
      |> paginate_urls(ui.page)

    socket =
      socket
      |> assign(%{ui: ui, data: data})
      |> stream(:urls, visible_urls, limit: @urls_per_page, reset: true)

    {:noreply, socket}
  end

  # Add a URI to the selected URIs
  def handle_event("select-uri", %{"uri" => uri}, socket) do
    data = socket.assigns.data
    all_uris = data.crawled_urls
    selected_urls = data.selected_urls

    selected_urls =
      if MapSet.member?(selected_urls, uri) do
        MapSet.delete(selected_urls, uri)
      else
        MapSet.put(selected_urls, uri)
      end

    data = %{data | selected_urls: selected_urls}
    ui = %{socket.assigns.ui | all_selected: MapSet.equal?(selected_urls, all_uris)}

    {:noreply, assign(socket, %{data: data, ui: ui})}
  end

  # Grab the next page, update the UI assigns, stream and update the page
  def handle_event("next-page", _params, socket) do
    ui = socket.assigns.ui
    next_page = ui.page - 1

    visible_urls =
      socket.assigns.data.crawled_urls
      |> paginate_urls(next_page)

    ui = %{ui | page: next_page, end_of_timeline?: length(visible_urls) < @urls_per_page}

    socket =
      socket
      |> stream(:urls, visible_urls, at: -1, limit: @urls_per_page)
      |> assign(:ui, ui)

    {:noreply, socket}
  end

  # Reset to page 1 of the pagination as we received the special overran params
  def handle_event("prev_page", %{"_overran" => true}, socket) do
    ui = socket.assigns.ui

    visible_urls =
      socket.assigns.data.crawled_urls
      |> paginate_urls(1)

    socket =
      stream(socket, :urls, visible_urls, limit: @urls_per_page, reset: true)
      |> assign(:ui, %{ui | page: 1, end_of_timeline?: false})

    {:noreply, socket}
  end

  def handle_event("prev_page", _params, socket) do
    ui = socket.assigns.ui
    next_page = ui.page - 1
    ui = %{ui | page: next_page, end_of_timeline?: false}

    visible_urls =
      socket.assigns.data.crawled_urls
      |> paginate_urls(next_page)
      |> Enum.reverse()

    socket =
      stream(socket, :urls, visible_urls, at: 0, limit: @urls_per_page)
      |> assign(:ui, ui)

    {:noreply, socket}
  end

  # Kick off the PDF Generation
  def handle_event("generate-pdf", _params, socket) do
    selected_urls = socket.assigns.data.selected_urls |> MapSet.to_list()

    ui = %{socket.assigns.ui | is_generating_pdf?: true}

    socket =
      socket
      |> assign(:ui, ui)
      |> start_async(:generate_pdf, fn ->
        PdfGenerator.generate_pdfs(selected_urls)
      end)

    {:noreply, assign(socket, ui: ui)}
  end

  def handle_async(:generate_pdf, {:ok, task_result}, socket) do
    case task_result do
      {:ok, job_id} ->
        data = %{socket.assigns.data | pdf_job_id: job_id}
        ui = %{socket.assigns.ui | is_generating_pdf?: false}

        assign(socket, %{data: data, ui: ui})

      {:error, _msg} ->
        ui = %{socket.assigns.ui | is_generating_pdf?: false}

        socket
        |> assign(:ui, ui)
        |> put_flash(:error, "An error occurred generating your PDF, please try again")
    end
    |> then(&{:noreply, &1})
  end

  # Receive Crawl Complete messages
  def handle_info({:crawl_complete, urls}, socket) do
    data = %{socket.assigns.data | crawled_urls: urls}
    ui = %{socket.assigns.ui | crawl_status: :completed}

    # Unsubscribe once the job completes
    Phoenix.PubSub.unsubscribe(Html2pdf.PubSub, data.crawl_job_id)

    paginated_uris = paginate_urls(urls, 1)

    socket =
      socket
      |> assign(%{ui: ui, data: data})
      |> stream(:urls, paginated_uris, limit: @urls_per_page, reset: true)

    {:noreply, socket}
  end

  # Handle any crash message back from the Oban Job
  #
  # In this case we want to unblock the user from trying again, resetting any data
  # like crawled URLs and reset the crawl status to the :not_started state.
  def handle_info(:crawl_error, socket) do
    data = %{socket.assigns.data | crawled_urls: MapSet.new()}
    ui = %{socket.assigns.ui | crawl_status: :not_started}

    # Unsubscribe once the job completes
    Phoenix.PubSub.unsubscribe(Html2pdf.PubSub, data.crawl_job_id)

    socket =
      socket
      |> assign(%{ui: ui, data: data})
      |> put_flash(
        :error,
        "Sorry, something went wrong while crawling the website. Please try again!"
      )

    {:noreply, socket}
  end

  # Receive Successfull download messages and clear the PDF Job ID because
  # on success the downloads are removed.
  def handle_info(:download_complete, socket) do
    data = %{socket.assigns.data | pdf_job_id: nil}

    {:noreply, assign(socket, :data, data)}
  end

  # Helper Functions

  # Paginate the URLs for the LiveView
  defp paginate_urls(crawled_urls, page) do
    start_index = (page - 1) * @urls_per_page
    end_index = page * @urls_per_page

    Enum.slice(crawled_urls, start_index..end_index)
    |> Enum.with_index(fn url, index ->
      %{id: index + start_index, url: url}
    end)
  end

  defp get_max_depth(), do: @max_depth
end
