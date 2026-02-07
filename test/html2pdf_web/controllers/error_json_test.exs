defmodule Html2pdfWeb.ErrorJSONTest do
  use Html2pdfWeb.ConnCase, async: true

  test "renders 404" do
    assert Html2pdfWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert Html2pdfWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
