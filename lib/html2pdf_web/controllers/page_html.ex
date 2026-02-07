defmodule Html2pdfWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use Html2pdfWeb, :html

  embed_templates "page_html/*"
end
