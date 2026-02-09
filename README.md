# Html2pdf

## Goal

The goal of this project is to re-write a library I made in Ruby / Ruby on Rails that crawled a website, converting it to a PDF. It is a WIP
with the initial implementation being done on a branch `feature/initial_featureset`. 

## Architecture
The current plan is to use Oban to ensure a limited number of crawls are kicked off at once. Each job ran in the Oban Queue will spawn off a GenServer
to act as the brain of the operation. For a URL and specific depth we will find any achor tags and their HREF to try crawl further as long as the next
link is not further in depth than the max depth.

Each URL is handled by an async Task, which uses Req and Floki to get the HREFs it needs.

The user can then select what PDFs they want and generate the PDF. PDF generation is handled with ChromicPDF as while WeasyPrint or other alternatives are out there,
they need docker containers or are paid. ChromicPDF let me rely on Webkit and Chromium.

PDFs are then combined using `pdftk`.

### Architecture Notes
Oban is currently used as a shortcut rather than setting up my own queue system using a GenServer. For this project I may experiment
with changing it over to a GenServer.

I also opted to write my own crawler knowing that the library [Crawly](https://hex.pm/packages/crawly) exists to experiment with a more raw OTP solution. 

If I were to create this project in a production environment I'd opt to use Crawly and Oban to manage these aspects as they have been battle tested,
and proven.

### Requirements
Ensure that Chrome and PDFTK are installed on your machine

### Running Locally
To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
