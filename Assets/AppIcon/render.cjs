// Rebuild with: node render.cjs
// Uses sharp / librsvg; install sharp or set SHARP_MODULE to its module path.
let sharp;
try { sharp = require(process.env.SHARP_MODULE || 'sharp'); }
catch { sharp = require('/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/sharp'); }
const variants = [
  ['16x16', 16], ['16x16@2x', 32], ['32x32', 32], ['32x32@2x', 64],
  ['128x128', 128], ['128x128@2x', 256], ['256x256', 256],
  ['256x256@2x', 512], ['512x512', 512], ['512x512@2x', 1024],
];
(async () => {
  for (const [name, size] of variants) {
    await sharp(size <= 64 ? 'icon-small.svg' : 'icon.svg', { density: 192 })
      .resize(size, size, { kernel: 'lanczos3' })
      .toColourspace('srgb').png().toFile(`icon_${name}.png`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
