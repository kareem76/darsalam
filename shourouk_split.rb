require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'mechanize'
require 'csv'
require 'json'

# --- ENV inputs ---
start_page = ENV['START_PAGE'].to_i
end_page = ENV['END_PAGE'].to_i
category_path = ENV['CATEGORY_PATH'] || '/books/arabic'

raise "Missing or invalid START_PAGE or END_PAGE" if start_page.zero? || end_page.zero?

# --- Setup Capybara ---
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

# --- Output paths ---
csv_file = "books_#{start_page}_#{end_page}.csv"
json_file = "books_#{start_page}_#{end_page}.json"
progress_file = "progress_#{start_page}_#{end_page}.txt"

# --- Prepare output ---
CSV.open(csv_file, 'w') do |csv|
  csv << %w[URL Title Author Price Summary Genre Publisher ISBN Year Image_URL Page]
end unless File.exist?(csv_file)

books = File.exist?(json_file) ? JSON.parse(File.read(json_file)) : []
existing_urls = books.map { |b| b['url'] }

# --- Helper for safe navigation ---
def safe_visit(path)
  visit(path)
  sleep 2
rescue => e
  puts "⚠️ Visit failed: #{e}"
  sleep 3
  retry
end

def wait_for_page_load(page_num)
  expect(page).to have_css('div.bookData', wait: 5)
rescue
  puts "⚠️ Page #{page_num} may not have loaded correctly"
end

# --- Start scraping ---
safe_visit(category_path)
(2..start_page).each do |num|
  link = all('div#Body_AspNetPager a', visible: true).find { |a| a.text.strip == num.to_s } rescue nil
  if link
    link.click
    wait_for_page_load(num)
  else
    puts "⚠️ Could not find page #{num}"
    break
  end
end

current_page = start_page

loop do
  break if current_page > end_page
  puts "📄 Scraping page #{current_page}..."

  book_links = all('div.bookData strong a').map { |a| a[:href] }.uniq

  book_links.each do |link|
    next if existing_urls.include?(link)

    begin
      book_page = agent.get(link)
    rescue => e
      puts "⚠️ Error fetching #{link}: #{e.message}"
      next
    end

    title     = book_page.at_css('.bookInnercontent h1')&.text&.strip || 'N/A'
    author    = book_page.at_css('a[href*="/books/author.aspx"]')&.text&.strip
    genre     = book_page.at_css('li#Body_LICategories a')&.text&.strip || 'N/A'
    publisher = book_page.at('li:contains("دار النشر") div.left a')&.text&.strip rescue 'N/A'
    isbn      = book_page.at('li:contains("ISBN") div.left')&.text&.strip rescue 'N/A'
    year      = book_page.at('li:contains("سنة النشر") div.left')&.text&.strip rescue 'N/A'
    summary   = book_page.at_css('meta[property="og:description"]')&.[]('content')&.strip || 'No summary'
    raw_image = book_page.at_css('#Body_rightCover img')&.[]('src')
    image_url = raw_image&.split('?')&.first
    price_tag = book_page.at_css('.discountPrice') || book_page.at_css('.price.priceNone')
    price     = price_tag&.text&.gsub('بعد التخفيض', '')&.gsub('السعر :', '')&.strip || 'N/A'

    book = {
      'url'       => link,
      'title'     => title,
      'author'    => author,
      'price'     => price,
      'summary'   => summary,
      'genre'     => genre,
      'publisher' => publisher,
      'isbn'      => isbn,
      'year'      => year,
      'image_url' => image_url,
      'page'      => current_page
    }

    books << book
    existing_urls << link

    CSV.open(csv_file, 'a') { |csv| csv << book.values }
    puts "✅ [#{current_page}] #{title}"
  end

  File.write(progress_file, current_page)

  begin
    next_btn = all('div#Body_AspNetPager a', visible: true).find { |a| a.text.strip == '>' }
    next_btn.click
    current_page += 1
    wait_for_page_load(current_page)
  rescue
    puts "⛔️ No next page at #{current_page}"
    break
  end
end

# Save final JSON once
File.write(json_file, JSON.pretty_generate(books, indent: '  '))
puts "✅ Finished pages #{start_page} to #{[current_page, end_page].min}"
