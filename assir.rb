require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'json'
require 'uri'

Capybara.default_driver = :selenium
Capybara.default_max_wait_time = 10

Capybara.register_driver :selenium do |app|
  Capybara::Selenium::Driver.new(app, browser: :firefox)
end

class AssirScraper
  include Capybara::DSL

  BASE_URL = "https://www.aseeralkotb.com"

  def scrape_all_book_links(publisher_url, book_count)
    total_pages = (book_count / 24.0).ceil
    all_links = []

    (1..total_pages).each do |page_number|
      paginated_url = "#{publisher_url}?books=#{page_number}"
      puts "Scraping book links from page: #{paginated_url}"

      visit paginated_url
      sleep 1

      links = all('a[href*="/ar/books/"]').map { |a| URI.join(BASE_URL, a[:href]).to_s }.uniq
      all_links.concat(links)

      puts "  Found #{links.size} books on this page"
    end

    all_links.uniq
  end

  def scrape_book_details(book_url)
    visit book_url
    sleep 1

    {
      title: find('h1', match: :first).text rescue nil,
      author: find('a[href*="/ar/authors/"]', match: :first).text rescue nil,
      publisher: find('a[href*="/ar/publishers/"]', match: :first).text rescue nil,
      category: find('a[href*="/ar/categories/"]', match: :first).text rescue nil,
      summary: find('div#Book_intro div.ng-binding', wait: 2).text.strip rescue nil,
      image: find('img.book-cover')[:src] rescue nil,
      url: book_url
    }
  end
end
if ARGV.length != 2
  puts "Usage: ruby assir.rb file.txt output.json"
  exit
end

input_file = ARGV[0]
output_file = ARGV[1]


scraper = AssirScraper.new
results = []

File.readlines(input_file).each do |line|
  next unless line.include?('Publisher:')

  publisher_name = line[/Publisher:\s*(.*?),/, 1]&.strip
  book_count = line[/Books Count:\s*(\d+)/, 1]&.to_i
  publisher_url = line[/URL:\s*(https?:\/\/\S+)/, 1]&.strip

  next unless publisher_name && book_count && publisher_url

  puts "\nScraping: #{publisher_name} (#{book_count} books)"
  begin
    book_links = scraper.scrape_all_book_links(publisher_url, book_count)
    puts "  Total book links: #{book_links.size}"

    book_links.each_with_index do |book_url, idx|
      puts "  (#{idx + 1}/#{book_links.size}) #{book_url}"
      book_data = scraper.scrape_book_details(book_url)
      book_data[:publisher] = publisher_name
      results << book_data
    end
  rescue => e
    puts "  Error scraping #{publisher_name}: #{e.message}"
  end
end

File.write(output_file, JSON.pretty_generate(results))
puts "\nDone! Saved #{results.size} books to #{output_file}"
