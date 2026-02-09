# Html2pdf

## Goal

The goal of this project is to re-write a library I made in Ruby / Ruby on Rails that crawled a website, converting it to a PDF. It is a WIP
with the initial implementation being done on a branch `feature/initial_featureset`. 

## Architecture
The current plan is to use Oban to ensure a limited number of crawls are kicked off at once. Each job ran in the Oban Queue will spawn off a GenServer
to act as the brain of the operation. For a URL and specific depth we will find any achor tags and their HREF to try crawl further as long as the next
link is not further in depth than the max depth.

Each URL is handled by an async Task, which uses [Req](https://hex.pm/packages/req) and [Floki](https://hex.pm/packages/floki) to get the HREFs it needs.

The user can then select what PDFs they want and generate the PDF. PDF generation is handled with [ChromicPDF](https://hex.pm/packages/chromic_pdf) as while WeasyPrint or other alternatives are out there,
they need docker containers or are paid. ChromicPDF let me rely on Webkit and Chromium.

PDFs are then combined using [`pdftk`](https://www.pdflabs.com/tools/pdftk-the-pdf-toolkit/) or the modern replacement [pdftk-java](https://gitlab.com/pdftk-java/pdftk)

### Architecture Notes
[Oban](https://hex.pm/packages/oban) is currently used as a shortcut rather than setting up my own queue system using a GenServer. For this project I may experiment
with changing it over to a GenServer.

I also opted to write my own crawler knowing that the library [Crawly](https://hex.pm/packages/crawly) exists to experiment with a more raw OTP solution. This project also does not do two things that Crawly does well:
- Limiting concurrent requests per domain in order to be respectful and not hammer their server
- Similarly, requests are not spaced like they are in Crawly
- This does not respect `robots.txt` for each website, which the library already implements.

If I were to create this project in a production environment I'd opt to use Crawly and Oban to manage these aspects as they have been battle tested,
and proven.


### Installation Requirements
Ensure that Chrome and PDFTK are installed on your machine

### Running Locally
To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
