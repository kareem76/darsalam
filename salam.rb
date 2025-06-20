# shourouk_split.rb
require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'

# Get page range from ENV
start_page = ENV['START_PAGE'].to_i
end_page = ENV['END_PAGE'].to_i
raise "Missing or invalid START_PAGE or END_PAGE" if start_page.zero? || end_page.zero?

# Configure Capybara to use Selenium with headless Chrome
Capybara.register_driver :selenium_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--window-size=1920,1080')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :selenium_headless
Capybara.app_host = 'https://www.shoroukbookstores.com'

include Capybara::DSL
agent = Mechanize.new

# File paths
csv_file_path = "books_#{start_page}_#{end_page}.csv"
json_file_path = "books_#{start_page}_#{end_page}.json"
progress_file_path = "progress_#{start_page}_#{end_page}.txt"

# Initialize CSV
unless File.exist?(csv_file_path)
  CSV.open(csv_file_path, 'w', headers: true) do |csv|
    csv << %w[URL Title Author Price Summary Genre Publisher ISBN Year Image_URL Page]
  end
end

# Initialize JSON
books = File.exist?(json_file_path) ? JSON.parse(File.read(json_file_path)) : []

# Visit the main listing page
visit('/books/arabic')
sleep 2

# Navigate to the start page
(2..start_page).each do |page_num|
  xpath = "//div[@id='Body_AspNetPager']//a[contains(@href, \"AspNetPager','#{page_num}'\")]"
  link = all(:xpath, xpath, visible: true).find { |el| el.text.strip == page_num.to_s }
  if link
    link.click
    sleep 1.5
  else
    puts "Couldn't find page link for #{page_num}"
    break
  end
end

current_page = start_page

# Start scraping loop
loop do
  break if current_page > end_page

  puts "Scraping page #{current_page}..."

  book_links = all('div.bookData strong a').map { |a| a[:href] }.uniq

  book_links.each do |link|
    next if books.any? { |b| b['url'] == link }

    begin
      book_page = agent.get(link)
    rescue => e
      puts "Error fetching #{link}: #{e}"
      next
    end

    title = book_page.at_css('.bookInnercontent h1')&.text&.strip || 'N/A'
    author = book_page.at_css('a[href*="/books/author.aspx"]')&.text&.strip
    genre = book_page.search('li#Body_LICategories a')&.text&.strip rescue 'N/A'
    publisher = book_page.search('li:contains("دار النشر") div.left a')&.text&.strip rescue 'N/A'
    isbn = book_page.search('li:contains("ISBN") div.left')&.text&.strip rescue 'N/A'
    year = book_page.search('li:contains("سنة النشر") div.left')&.text&.strip rescue 'N/A'
    raw_image_url = book_page.at_css('#Body_rightCover img')&.[]('src')
    image_url = raw_image_url&.split('?')&.first

    summary = book_page.at_css('meta[property="og:description"]')&.[]('content')&.strip || 'Summary not found.'

    discount = book_page.at_css('.discountPrice')
    price = if discount
              discount.text.gsub('بعد التخفيض', '').strip
            else
              book_page.at_css('.price.priceNone')&.text&.gsub('السعر :', '')&.strip
            end

    book = {
      'url' => link,
      'title' => title,
      'author' => author,
      'price' => price,
      'summary' => summary,
      'genre' => genre,
      'publisher' => publisher,
      'isbn' => isbn,
      'year' => year,
      'image_url' => image_url,
      'page' => current_page
    }

    books << book
    CSV.open(csv_file_path, 'a') { |csv| csv << book.values }
    File.write(json_file_path, JSON.pretty_generate(books))
  end

  File.write(progress_file_path, current_page)

  # Go to next page
  begin
    next_btn = all('div#Body_AspNetPager a', visible: true).find { |a| a.text.strip == '>' }
    next_btn.click
    current_page += 1
    sleep 2
  rescue => e
    puts "No next page or error: #{e}"
    break
  end
end

puts "✅ Done: scraped pages #{start_page} to #{[end_page, current_page].min}"
