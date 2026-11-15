import { chromium } from 'playwright';
import { resolve } from 'node:path';

const root = resolve(process.cwd(), 'formal_ai_documents');
const files = ['AI_Data_Analysis_Report', 'AI_Formula_Specification'];
const browser = await chromium.launch({ headless: true });
try {
  for (const name of files) {
    const page = await browser.newPage({ viewport: { width: 1240, height: 1754 }, deviceScaleFactor: 1 });
    await page.goto(`file://${root}/${name}.html`, { waitUntil: 'networkidle' });
    await page.pdf({
      path: `${root}/${name}.pdf`,
      format: 'A4',
      printBackground: true,
      displayHeaderFooter: false,
      margin: { top: '17mm', right: '16mm', bottom: '16mm', left: '16mm' },
    });
    await page.screenshot({ path: `${root}/${name}-preview.png`, fullPage: true });
    await page.close();
  }
} finally {
  await browser.close();
}
