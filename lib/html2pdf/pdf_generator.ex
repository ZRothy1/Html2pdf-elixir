defmodule Html2pdf.PdfGenerator do
  @moduledoc """
  This module will drive the PDF generation using PDFTK and ChromicPDF

  First, we generate the PDFs and store them to a specific directory in
  the tmp dir using ChromicPDF. Then once that is complete we use PDFTK
  to combine the PDFs all into one.

  The pages of the combined PDF are combined in the order they are received. The order
  should be breadth first rather than depth first or a random order. This is due to the
  way the crawler operated, using a GenServer. Each URL was processed in a queue in the order
  it received, and each page's links are sent in the order they are found.
  """

  require Logger

  def generate_pdfs(urls) do
    job_id = TypeID.new("pdf") |> TypeID.to_string()
    tmp_dir = System.tmp_dir() <> "/#{job_id}"

    case File.mkdir(tmp_dir) do
      :ok ->
        pdf_files =
          Enum.map(urls, fn url -> generate_pdf(url, tmp_dir) end)
          |> Enum.reject(&is_nil/1)

        # On success we return the JobID created which is unique enough
        # to avoid random guesses. We also clean up the generated PDF files
        # to avoid leaving them around orphaned
        case combine_pdfs(tmp_dir, pdf_files) do
          {:ok, _file_name} ->
            {:ok, job_id}

          {:error, _} = err ->
            err
        end

      err ->
        Logger.error("Could not create tmp directory - #{tmp_dir}: #{inspect(err)}")

        {:error, "Could not create tmp directory"}
    end
  end

  defp generate_pdf(url, tmp_dir) do
    file_name = (TypeID.new("pdf") |> TypeID.to_string()) <> ".pdf"

    try do
      :ok = ChromicPDF.print_to_pdf({:url, url}, output: tmp_dir <> "/" <> file_name)

      file_name
    rescue
      e ->
        Logger.error("Skipping PDF generation for #{url}: #{inspect(e)}")

        nil
    end
  end

  # Combine the PDFs using PDFTK
  #
  # Parameters:
  # * `tmp_dir` - The temp directory holding all the files
  # * `pdf_files` - the list of generated PDF files that exist in `tmp_dir`
  #
  # If PDFTK fails, no file is combined. On success or failure we still clean up
  # the temp directory
  #
  # Returns {:ok, base64_file :: binary()} or {:error, msg :: string()}
  defp combine_pdfs(tmp_dir, pdf_files) do
    args = pdf_files ++ ["cat", "output", "combined.pdf"]
    opts = [cd: tmp_dir, stderr_to_stdout: true]

    case System.cmd("pdftk", args, opts) do
      {_, 0 = _exit_code} ->
        case File.read("#{tmp_dir}/combined.pdf") do
          {:ok, file_binary} ->
            {:ok, Base.encode64(file_binary)}

          {:error, err} ->
            Logger.error("Received #{inspect(err)} when reading the combined PDF in #{tmp_dir}.")

            {:error, "Could not read combined PDF file"}
        end

      {msg, exit_code} ->
        Logger.error("Received #{exit_code} from PDFTK with the message: #{msg}")

        {:error, "Could not combine the PDFs"}
    end
  end

  @doc """
  Clean up and remove any temporary files

  Parameters:
  * `tmp_dir` - the temp directory for a specific PDF combination job

  This removes any and all files in the directory, including the original PDFs as well
  as the combined PDF to ensure no data is left over

  Returns :ok on success or `{:error, msg :: string()}` on failure.
  """
  def cleanup_tmp_dir(tmp_dir) do
    case File.rm_rf(tmp_dir) do
      {:ok, _} ->
        :ok

      {:error, reason, file_or_dir} ->
        Logger.warning(
          "Failed to clean up #{tmp_dir}. Recursively removing it received a #{inspect(reason)} error for #{file_or_dir}."
        )

        {:error, "Could not clean up"}
    end
  end
end
