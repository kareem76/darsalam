const fs = require('fs');
const { chromium } = require('playwright');
const cheerio = require('cheerio');
const args = process.argv.slice(2);
const START_PAGE = parseInt(args[0]) || 2002;
const END_PAGE = parseInt(args[1]) || 3605;

const filename = `books_${START_PAGE}-${END_PAGE}.ndjson`;
const stream = fs.createWriteStream(filename, { flags: 'a' });

const STREAM = fs.createWriteStream('books.ndjson', { flags: 'a' });
const COOKIES_PATH = 'cookies.json';



(async () => {
  const browser = await chromium.launch({ headless: false }); // use xvfb-run
  const context = await browser.newContext();

  // Load cookies if available
  if (fs.existsSync(COOKIES_PATH)) {
    const cookies = JSON.parse(fs.readFileSync(COOKIES_PATH, 'utf-8'));
    await context.addCookies(cookies);
    console.log('🔁 Loaded cookies');
  }

  const page = await context.newPage();

  for (let currentPage = START_PAGE; currentPage <= END_PAGE; currentPage++) {
    const listUrl = `https://www.aseeralkotb.com/ar/books?page=${currentPage}`;
    console.log(`📄 Visiting list page ${currentPage}: ${listUrl}`);

    try {
      await page.goto(listUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

      if ((await page.title()) === 'Just a moment...') {
        console.log('⏳ Cloudflare challenge... waiting...');
        await page.waitForFunction(
          () => document.title !== 'Just a moment...',
          { timeout: 20000 }
        );
        await page.waitForLoadState('networkidle');
      }

      const html = await page.content();
      const $ = cheerio.load(html);

      const bookLinks = [];
      $('a.hover\\:no-underline.text-center').each((i, el) => {
        const href = $(el).attr('href');
        if (href) bookLinks.push(href);
      });

      console.log(`🔗 Found ${bookLinks.length} books on page ${currentPage}`);

      for (const bookRelUrl of bookLinks) {
        const bookUrl = new URL(bookRelUrl, 'https://www.aseeralkotb.com').href;
        console.log(`  📖 Visiting book: ${bookUrl}`);

        try {
          await page.goto(bookUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

          const bookHtml = await page.content();
          const $$ = cheerio.load(bookHtml);

          const title = $$('h1[itemprop="name"]').first().text().trim();
          const image_url = $$('img[itemprop="contentUrl"]').attr('src') || 'N/A';

          let price = 'N/A';
          $$('dt').each((i, el) => {
            const dtText = $$(el).text().trim();
            if (dtText === 'قبل:') {
              const dd = $$(el).next('dd');
              if (dd.length) price = dd.text().trim().replace(/\s+/g, ' ');
            }
          });
          if (price === 'N/A') {
            price = $$('span[itemprop=price]').text().trim() || 'N/A';
          }

          const summary = $$('div[itemprop="description"] span').first().text().trim() || 'N/A';

          const getField = (label) => {
            let val = 'N/A';
            $$('.single-book__metadata .grid').each((i, el) => {
              const dt = $$(el).find('dt').text().trim();
              if (dt.includes(label)) {
                val = $$(el).find('dd').text().trim().replace(/\s+/g, ' ');
              }
            });
            return val;
          };

          const authors = getField('المؤلفون');
          const year = getField('سنة النشر');
          const publisher = getField('دار النشر');
          const genre = getField('الأقسام');
          const isbn = getField('ISBN');

          const bookData = {
            title,
            authors,
            price,
            year,
            publisher,
            genre,
            isbn,
            summary,
            image_url,
            bookUrl,
          };

          console.log(`    ✅ ${title}`);
          STREAM.write(JSON.stringify(bookData) + '\n');

        } catch (err) {
          console.error(`    ❌ Failed book ${bookUrl}: ${err.message}`);
        }

        await page.waitForTimeout(1000 + Math.random() * 2000); // safe pacing
      }
    } catch (err) {
      console.error(`❌ Page ${currentPage} error: ${err.message}`);
    }
  }

  fs.writeFileSync(COOKIES_PATH, JSON.stringify(await context.cookies(), null, 2));
  STREAM.end();
  await browser.close();
})();
