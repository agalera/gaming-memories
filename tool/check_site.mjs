import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('site');
const pages = ['index.html', 'docs.html'];
const failures = [];

function record(condition, message) {
  if (!condition) failures.push(message);
}

const idsByPage = new Map();

for (const page of pages) {
  const filePath = path.join(root, page);
  const content = fs.readFileSync(filePath, 'utf8');
  const ids = new Set([...content.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]));
  idsByPage.set(page, ids);
  record(ids.size === [...content.matchAll(/\sid="([^"]+)"/g)].length, `${page} has a duplicate id.`);

  for (const match of content.matchAll(/(?:src|href)="([^"]+)"/g)) {
    const reference = match[1];
    if (/^(?:https?:|mailto:)/.test(reference)) continue;

    const [targetFile, fragment] = reference.split('#');
    const localFile = targetFile || page;
    const resolved = path.resolve(root, localFile);
    record(resolved.startsWith(root), `${page} has an unsafe path: ${reference}`);
    record(fs.existsSync(resolved), `${page} has a missing file: ${reference}`);

    if (fragment && pages.includes(localFile)) {
      const targetIds = idsByPage.get(localFile);
      if (targetIds) record(targetIds.has(fragment), `${page} has a missing anchor: ${reference}`);
    }
  }
}

for (const page of pages) {
  const content = fs.readFileSync(path.join(root, page), 'utf8');
  for (const match of content.matchAll(/href="([^"]*#([^"]+))"/g)) {
    const [targetFile] = match[1].split('#');
    const localFile = targetFile || page;
    if (!pages.includes(localFile)) continue;
    record(idsByPage.get(localFile)?.has(match[2]), `${page} has a missing anchor: ${match[1]}`);
  }
}

const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
for (const match of css.matchAll(/url\(["']?([^"')]+)["']?\)/g)) {
  const reference = match[1];
  if (/^(?:data:|https?:)/.test(reference)) continue;
  record(fs.existsSync(path.resolve(root, reference)), `styles.css has a missing file: ${reference}`);
}

const screenshotCarouselRule = css.match(/\.screenshot-carousel\s*\{([^}]*)\}/)?.[1] || '';
record(
  !/\bbackground(?:-color)?\s*:/.test(screenshotCarouselRule),
  'styles.css paints a background behind the transparent screenshots.',
);

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log(`Checked ${pages.length} pages and all local references.`);
