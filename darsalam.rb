require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'set'

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

include Capybara::DSL

def safe_visit(url, retries = 3)
  attempts = 0
  begin
    visit url
  rescue Net::ReadTimeout, Selenium::WebDriver::Error::UnknownError => e
    attempts += 1
    puts "⚠️ Timeout visiting #{url}, attempt #{attempts} of #{retries}"
    if attempts < retries
      sleep 5
      retry
    else
      puts "❌ Failed to visit #{url} after #{retries} attempts: #{e.message}"
    end
  end
end

file_arg = ARGV[0] || 'file.txt'
chunk = File.basename(file_arg)
json_path = "books-output-#{chunk}.json"

category_urls = File.readlines(file_arg, chomp: true).map.with_index do |line, i|
  url = line[/(https?:\/\/\S+)/, 1]
  if url
    url.strip
  else
    puts "⚠️ لم أجد رابطًا في السطر ##{i + 1}: #{line.inspect}"
    nil
  end
end.compact

File.write(json_path, "[\n") unless File.exist?(json_path)

def scrape_book_details
  unless page.has_selector?('div.book-title', wait: 15)
    puts "⚠️ Skipping page: missing book title"
    return nil
  end

  doc = Nokogiri::HTML(page.html)
  {
    title: doc.at_css('div.book-title')&.text&.strip,
    author: doc.at_css('a[ng-repeat*="Publisher in"]')&.text&.strip,
    category: doc.at_css('a[ng-repeat*="subject_nam"]')&.text&.strip,
    year: doc.at_css('div[ng-show*="PrintYear"] span.ng-binding')&.text&.strip,
    isbn: doc.at_css('div[ng-show*="BookIsbn"] span.ng-binding')&.text&.strip,
    price: doc.at_css('span.after-price')&.text&.strip,
    publisher: doc.at_css('div[ng-hide*="Publishing_name"] a')&.text&.strip,
    imgurl: doc.at_css('img[src*="/Files/Images"]')&.[]('src'),
    bookurl: current_url
  }
end

category_urls.each do |url|
  puts "\n🟦 Visiting category: #{url}"
  safe_visit(url)
  sleep 5

  next unless page.has_selector?('h6.archive-title a', wait: 10)

  scraped_links = Set.new

  loop do
    book_links = all('h6.archive-title a').map { |a| a[:href] }.uniq

    book_links.each do |link|
      next if scraped_links.include?(link)
      scraped_links << link

      safe_visit(link)
      sleep 5

      book_data = scrape_book_details
      if book_data.nil? || book_data[:title].nil?
        puts "❌ Skipped: missing or invalid data"
        next
      end

      puts "✅ Scraped: #{book_data[:title]}"
      File.open(json_path, 'a') do |f|
        f.puts JSON.pretty_generate(book_data) + ","
      end

       safe_visit(url) 
      sleep 10
    end

    next_button = all('a.page-link').find { |a| a.text.include?('>') rescue false }
    if next_button
      next_button.click
      sleep 5
    else
      puts "✅ Finished category"
      break
    end
  end
end

# Finalize JSON file
content = File.read(json_path).strip.chomp(',')
File.write(json_path, content + "\n]\n")
puts "✅ Done! All books saved to #{json_path}"
