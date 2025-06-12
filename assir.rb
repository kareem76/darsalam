require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
$stdout.sync = true

Capybara.register_driver :chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :chrome
Capybara.default_max_wait_time = 20

class AseerAlKotbScraper
  include Capybara::DSL

  BASE_URL = "https://www.aseeralkotb.com"

  def initialize
    @book_links = []
  end

 def scrape_all_book_links(publisher_url, book_count)
  total_pages = (book_count / 24.0).ceil
  all_links = []

  (1..total_pages).each do |page_number|
    paginated_url = "#{publisher_url}?books=#{page_number}"
    puts "Scraping book links from page: #{paginated_url}"

    visit paginated_url
    if has_css?('a[href*="/ar/books/"]', wait: 5)
      links = all('a[href*="/ar/books/"]', visible: true).map do |a|
        href = a[:href]
        URI.join("https://www.aseeralkotb.com", href).to_s if href
      end.compact.uniq

      all_links.concat(links)
      puts "  Found #{links.size} books"
    else
      puts "  Warning: No book links found on this page."
    end
  end

  all_links.uniq
end


  def scrape_book_details(book_url)
    visit book_url
    sleep 2

    doc = Nokogiri::HTML(page.html)

    title = doc.at_css('h1[itemprop="name"]')&.text&.strip || "N/A"
    image_url = doc.at_css('img[itemprop="contentUrl"]')&.[]('src') || "N/A"
    json_ld = doc.at('script[type="application/ld+json"]')&.text
    summary = json_ld ? (JSON.parse(json_ld)["description"] rescue "N/A") : "N/A"
    authors = doc.css('dt:contains("المؤلفون") + dd a').map(&:text).map(&:strip).join(', ')
    year = doc.at_css('dt:contains("سنة النشر") + dd')&.text&.strip || "N/A"
    publisher = doc.at_css('dt:contains("دار النشر") + dd span[itemprop="name"]')&.text&.strip || "N/A"
    genre = doc.at_css('dt:contains("الأقسام") + dd')&.text&.strip || "N/A"
    isbn = doc.at_css('dt:contains("ISBN") + dd')&.text&.strip || "N/A"
    price = doc.at_css('dt:contains("قبل:") + dd span')&.text&.strip || "N/A"

    {
      title: title,
      image_url: image_url,
      summary: summary,
      authors: authors,
      year: year,
      publisher: publisher,
      genre: genre,
      isbn: isbn,
      price: price,
      book_link: book_url
    }
  end
end

# === Main script ===

input_file = ARGV[0] || 'list.txt'
output_file = ARGV[1] || 'results.json'

scraper = AseerAlKotbScraper.new
scraped_urls = []
first_item = true

# Open file and write opening bracket
json_file = File.open(output_file, "w:utf-8")
json_file.write("[\n")

# Ensure JSON array closes properly on exit
at_exit do
  json_file.write("\n]\n")
  json_file.close
  puts "Saved results to #{output_file}"
end

File.readlines(input_file).each do |line|
  next unless line.include?('Publisher:')

  publisher_name = line[/Publisher:\s*(.*?),/, 1]&.strip
  book_count = line[/Books Count:\s*(\d+)/, 1]&.to_i
  publisher_url = line[/URL:\s*(https?:\/\/\S+)/, 1]&.strip

  next unless publisher_name && book_count && publisher_url

  puts "Scraping: #{publisher_name} (#{book_count} books)"
  begin
    book_links = scraper.scrape_all_book_links(publisher_url, book_count)
  
book_links.each do |page_url, urls|
  puts "Scraping book links from page: #{page_url}"

  urls.each do |book_url|
    next if scraped_urls.include?(book_url)

    begin
      details = scraper.scrape_book_details(book_url)
      scraped_urls << book_url

      json_file.write(",\n") unless first_item
      json_file.write(JSON.pretty_generate(details))
      json_file.flush
      first_item = false

      puts "Scraped: #{details[:title]}"
    rescue => e
      warn "Failed to scrape book: #{book_url} (#{e.message})"
    end
  end
end

  rescue => e
    warn "Failed publisher #{publisher_name}: #{e.message}"
  end
end
