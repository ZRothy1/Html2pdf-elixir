defmodule Html2pdf.Repo do
  use Ecto.Repo,
    otp_app: :html2pdf,
    adapter: Ecto.Adapters.Postgres
end
