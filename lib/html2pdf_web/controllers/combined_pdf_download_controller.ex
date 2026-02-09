defmodule Html2pdfWeb.Controllers.CombinedPdfDownloadController do
  @moduledoc """
  There isn't a great method of sending downloads via a LiveView page without
  managing custom JS. To simplify the download process, this controller is dedicated
  to sending the PDF to the user upon request, and cleaning up any files necessary.
  """
  use Html2pdfWeb, :controller

  alias Html2pdf.PdfGenerator

  def download(conn, %{"job_id" => job_id} = _params) do
    tmp_dir = System.tmp_dir() <> "/#{job_id}"
    combined_pdf_path = tmp_dir <> "/combined.pdf"

    case File.read(combined_pdf_path) do
      {:ok, binary} ->
        PdfGenerator.cleanup_tmp_dir(tmp_dir)

        send_download(conn, {:binary, binary}, disposition: :attachment, filename: "combined.pdf")

      {:error, _} ->
        PdfGenerator.cleanup_tmp_dir(tmp_dir)

        send_resp(conn, "500", "An error occurred downloading your file, please try again")
    end
  end
end
