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
file_arg = ARGV[0] || 'file.txt'
chunk = File.basename(file_arg)  # keeps 'file1.txt'
json_path = "books-output-#{chunk}.json"

category_urls = File.readlines(file_arg, chomp: true).map.with_index do |line, i|
  if line.include?("=>")
    url = line.split('=>').last&.strip
    url unless url.nil? || url.empty?
  else
    puts "⚠️ تخطيت سطر غير صالح ##{i + 1}: #{line.inspect}"
    nil
  end
end.compact

File.write(json_path, "[\n") unless File.exist?(json_path)



def scrape_book_details
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
  safe_visit(url)  # if you use safe_visit method, otherwise use `visit url`
  sleep 2

  # ✅ Add this line to skip category if nothing was loaded
  next unless page.has_selector?('h6.archive-title a', wait: 10)

  loop do
    book_links = all('h6.archive-title a').map { |a| a[:href] }

    book_links.each do |link|
      safe_visit(link)
      sleep 5

      book_data = scrape_book_details
      puts "✅ Scraped: #{book_data[:title]}"

      File.open(json_path, 'a') do |f|
        f.puts JSON.pretty_generate(book_data) + ","
      end

      visit url
      sleep 1
    end

    # Your pagination logic here (not shown)
    break unless page.has_selector?('a.next')  # Example condition
    click_on 'التالي' rescue break
    sleep 10
  end
end


  # Fix: Use link instead of button
  next_button = all('a.page-link').find { |a| a.text.include?('>') rescue false }

  if next_button
    next_button.click
    sleep 10
  else
    puts "✅ Finished category"
   break
    end
  end # ← end of loop
end # ← end of category_urls.each

# Fix trailing comma and close array
content = File.read(json_path).strip.chomp(',')
File.write(json_path, content + "\n]\n")
puts "✅ Done! All books saved to #{json_path}"
