defmodule Html2pdfWeb.PageController do
  use Html2pdfWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
