// Regenerate PNG resources from the editable SVG. Requires the sharp package.
// NODE_PATH=/path/to/node_modules node scripts/generate-branding.cjs
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const root = path.resolve(__dirname, '..');
const appMedia = path.join(root, 'AppScope/resources/base/media');
const entryMedia = path.join(root, 'entry/src/main/resources/base/media');

async function main() {
  const source = await fs.readFile(path.join(appMedia, 'lexiclash_icon.svg'), 'utf8');
  const backgroundRect = /<rect[^>]*\/>/;
  const background = source.match(backgroundRect)[0].replace('rx="240"', 'rx="0"');
  const foreground = source.replace(backgroundRect, '');
  const backgroundSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">${background}</svg>`;
  const foregroundPng = await sharp(Buffer.from(foreground)).png().toBuffer();
  const backgroundPng = await sharp(Buffer.from(backgroundSvg)).png().toBuffer();
  const iconPng = await sharp(Buffer.from(source)).png().toBuffer();

  // Layered launcher icons need an opaque, full-bleed background. The system
  // applies its own mask; rounded corners belong only to the in-app icon.
  for (const media of [appMedia, entryMedia]) {
    await fs.writeFile(path.join(media, 'foreground.png'), foregroundPng);
    await fs.writeFile(path.join(media, 'background.png'), backgroundPng);
  }
  await fs.writeFile(path.join(appMedia, 'app_icon.png'), iconPng);
  await fs.writeFile(path.join(entryMedia, 'startIcon.png'), iconPng);
  await sharp(Buffer.from(source)).resize(256, 256).png()
    .toFile(path.join(root, 'docs/lexiclash-icon-preview.png'));
  console.log('Generated LexiClash app, launcher, and startup icons (1024 × 1024).');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
