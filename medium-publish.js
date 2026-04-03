#!/usr/bin/env node
/**
 * medium-publish.js
 * Imports blog posts to Medium via the Import tool and auto-publishes them.
 * Uses saved session cookies. Runs Firefox in HEADED mode to pass Cloudflare.
 *
 * Usage:
 *   Single post:  node medium-publish.js <url>
 *   Batch file:   node medium-publish.js --batch <file-with-urls>
 */

const { firefox } = require('playwright');
const fs = require('fs');
const path = require('path');

const COOKIES_FILE = path.join(process.env.HOME, '.openclaw/medium-cookies.json');
const LOG_FILE = path.join(__dirname, 'generate.log');
const CLOUDFLARE_WAIT_MS = 45000; // 45s for user to click Cloudflare if needed

function log(msg) {
  const line = `[${new Date().toISOString()}] [medium] ${msg}`;
  console.log(line);
  fs.appendFileSync(LOG_FILE, line + '\n');
}

async function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function loadCookies() {
  if (!fs.existsSync(COOKIES_FILE)) {
    log('ERROR: Cookies file not found at ' + COOKIES_FILE);
    process.exit(1);
  }
  const rawCookies = JSON.parse(fs.readFileSync(COOKIES_FILE, 'utf8'));
  return rawCookies
    .filter(c => c.name && c.value)
    .map(c => ({
      name: c.name,
      value: c.value,
      domain: c.domain.startsWith('.') ? c.domain : '.' + c.domain,
      path: c.path || '/',
      secure: c.secure || false,
      httpOnly: c.httpOnly || false,
      sameSite: c.sameSite === 'no_restriction' ? 'None'
              : c.sameSite === 'strict' ? 'Strict'
              : c.sameSite === 'lax' ? 'Lax'
              : 'None',
      expires: c.expirationDate ? Math.floor(c.expirationDate) : -1,
    }));
}

async function saveCookies(context) {
  try {
    const cookies = await context.cookies(['https://medium.com']);
    // Merge back into original format for Cookie-Editor compatibility
    const saved = cookies.map(c => ({
      name: c.name,
      value: c.value,
      domain: c.domain,
      hostOnly: !c.domain.startsWith('.'),
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
      sameSite: c.sameSite === 'None' ? 'no_restriction'
               : c.sameSite === 'Strict' ? 'strict'
               : c.sameSite === 'Lax' ? 'lax'
               : null,
      session: c.expires === -1,
      firstPartyDomain: '',
      partitionKey: null,
      expirationDate: c.expires > 0 ? c.expires : undefined,
      storeId: null,
    }));
    fs.writeFileSync(COOKIES_FILE, JSON.stringify(saved, null, 2));
    log('Cookies refreshed and saved.');
  } catch (e) {
    log(`WARN: Could not save cookies: ${e.message}`);
  }
}

async function publishOne(page, articleUrl) {
  const canonicalUrl = articleUrl;
  log(`Importing: ${articleUrl}`);

  // Navigate to import page
  log('Navigating to medium.com/p/import ...');
  await page.goto('https://medium.com/p/import', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(2000);

  const currentUrl = page.url();

  // Cloudflare check
  if (currentUrl.includes('challenge') || await page.$('text=Verify you are human') !== null) {
    log('⚠️  Cloudflare challenge detected. Please click "Verify you are human" in the browser window.');
    log(`Waiting up to ${CLOUDFLARE_WAIT_MS / 1000}s for you to complete it...`);
    await page.waitForURL(url => !url.includes('challenge'), { timeout: CLOUDFLARE_WAIT_MS });
    await sleep(2000);
    log('Cloudflare passed. Continuing...');
  }

  // Login check
  if (page.url().includes('/login') || page.url().includes('/signin') || page.url().includes('/m/signin')) {
    log('ERROR: Not authenticated — cookies may have expired. Re-export from browser.');
    return false;
  }

  // Enter article URL
  log('Entering article URL...');
  try {
    const input = await page.waitForSelector(
      'input[type="url"], input[placeholder*="http"], input[name*="url"], input[placeholder*="URL"], input[placeholder*="link"]',
      { timeout: 15000 }
    );
    await input.fill(articleUrl);
    await sleep(500);
  } catch (e) {
    log(`ERROR: Could not find URL input: ${e.message}`);
    await page.screenshot({ path: path.join(__dirname, 'medium-debug.png') });
    log('Debug screenshot saved.');
    return false;
  }

  // Click Import
  log('Clicking Import...');
  try {
    const importBtn = await page.waitForSelector(
      'button:has-text("Import"), button:has-text("import")',
      { timeout: 10000 }
    );
    await importBtn.click();
  } catch (e) {
    log(`ERROR: Could not find Import button: ${e.message}`);
    return false;
  }

  // Wait for editor
  log('Waiting for editor to load...');
  try {
    await page.waitForURL(url => url.includes('/p/') && !url.includes('/import'), { timeout: 60000 });
    await sleep(3000);
  } catch (e) {
    // Sometimes no navigation, editor loads in place
    await sleep(5000);
  }
  log(`Editor loaded: ${page.url()}`);

  // Set canonical URL
  log('Attempting to set canonical URL...');
  try {
    const moreBtn = await page.$('button[aria-label*="more" i], button[aria-label*="setting" i], [data-testid="post-settings-button"]');
    if (moreBtn) {
      await moreBtn.click();
      await sleep(1000);
      const canonicalInput = await page.$('input[placeholder*="canonical" i], input[placeholder*="original" i], input[name*="canonical" i]');
      if (canonicalInput) {
        await canonicalInput.fill(canonicalUrl);
        log(`Canonical URL set: ${canonicalUrl}`);
        await sleep(500);
      } else {
        log('WARN: Canonical field not found — set manually if needed.');
      }
      const closeBtn = await page.$('button[aria-label*="close" i], button[aria-label*="done" i]');
      if (closeBtn) await closeBtn.click();
      await sleep(500);
    } else {
      log('WARN: Settings button not found — canonical URL not set.');
    }
  } catch (e) {
    log(`WARN: Canonical URL step failed: ${e.message}`);
  }

  // Click Publish
  log('Clicking Publish...');
  try {
    const publishBtn = await page.waitForSelector(
      'button:has-text("Publish"), button:has-text("publish")',
      { timeout: 15000 }
    );
    await publishBtn.click();
    await sleep(2000);
  } catch (e) {
    log(`ERROR: Could not find Publish button: ${e.message}`);
    return false;
  }

  // Confirm publish dialog
  try {
    const confirmBtn = await page.waitForSelector(
      'button:has-text("Publish now"), button:has-text("Publish story"), button:has-text("Publish to")',
      { timeout: 8000 }
    );
    if (confirmBtn) {
      await confirmBtn.click();
      log('Confirmed publish dialog.');
      await sleep(3000);
    }
  } catch (e) {
    // No confirm dialog — may already be published
  }

  log(`✅ SUCCESS: ${articleUrl} → ${page.url()}`);
  return true;
}

async function main() {
  const args = process.argv.slice(2);
  let urls = [];

  if (args[0] === '--batch' && args[1]) {
    urls = fs.readFileSync(args[1], 'utf8').trim().split('\n').filter(Boolean);
  } else if (args[0]) {
    urls = [args[0]];
  } else {
    log('ERROR: No URL or --batch file provided.');
    process.exit(1);
  }

  log(`Starting batch of ${urls.length} post(s). Opening browser window...`);

  const browser = await firefox.launch({
    headless: false,
    slowMo: 100,
  });

  const context = await browser.newContext();
  await context.addCookies(loadCookies());
  const page = await context.newPage();

  let success = 0;
  let failed = 0;

  for (let i = 0; i < urls.length; i++) {
    const url = urls[i].trim();
    if (!url) continue;
    log(`\n[${i + 1}/${urls.length}] Processing...`);
    const ok = await publishOne(page, url);
    if (ok) success++; else failed++;
    if (i < urls.length - 1) {
      log('Waiting 10s before next post...');
      await sleep(10000);
    }
  }

  // Save refreshed cookies
  await saveCookies(context);

  log(`\nDone. ${success} published, ${failed} failed.`);
  await browser.close();
}

main().catch(e => {
  log(`FATAL: ${e.message}`);
  process.exit(1);
});
