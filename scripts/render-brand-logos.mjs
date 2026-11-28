#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '@playwright/test';

const root = path.resolve(import.meta.dirname, '..');
const brandDir = path.join(root, 'docs', 'brand');
const assetsDir = path.join(root, 'ios-native', 'OpenTokenUsage', 'Shared', 'BrandLogos.xcassets');

const logos = [
  { id: 'codex', svg: 'codex.svg', assetName: 'logo-codex' },
  { id: 'antigravity', svg: 'antigravity.svg', assetName: 'logo-antigravity' },
];

fs.mkdirSync(assetsDir, { recursive: true });
fs.writeFileSync(
  path.join(assetsDir, 'Contents.json'),
  JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n'
);

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 512, height: 512 }, deviceScaleFactor: 1 });
  for (const logo of logos) {
    const svgPath = path.join(brandDir, logo.svg);
    const svgMarkup = fs.readFileSync(svgPath, 'utf8');
    await page.setContent(`<!doctype html>
      <html>
        <head>
          <style>
            html, body { margin: 0; padding: 0; width: 512px; height: 512px; background: transparent; overflow: hidden; }
            svg { width: 512px; height: 512px; display: block; }
          </style>
        </head>
        <body>${svgMarkup}</body>
      </html>`);

    const imagesetDir = path.join(assetsDir, `${logo.assetName}.imageset`);
    fs.mkdirSync(imagesetDir, { recursive: true });
    const pngName = `${logo.assetName}.png`;
    await page.screenshot({
      path: path.join(imagesetDir, pngName),
      omitBackground: true,
      clip: { x: 0, y: 0, width: 512, height: 512 },
    });

    fs.writeFileSync(
      path.join(imagesetDir, 'Contents.json'),
      JSON.stringify(
        {
          images: [
            {
              filename: pngName,
              idiom: 'universal',
            },
          ],
          info: {
            author: 'xcode',
            version: 1,
          },
        },
        null,
        2
      ) + '\n'
    );
    console.log(`Rendered ${logo.svg} -> ${path.relative(root, path.join(imagesetDir, pngName))}`);
  }
} finally {
  await browser.close();
}
