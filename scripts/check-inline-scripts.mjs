import { readFileSync } from "node:fs";
import { Script } from "node:vm";

const htmlFiles = [
  "index.html",
  "admin/index.html",
  "admin/reviews.html",
  "admin/forum.html",
  "forum.html",
];
const jsFiles = ["community-reviews.js"];

let checked = 0;
const errors = [];

for (const file of htmlFiles) {
  let html;
  try {
    html = readFileSync(file, "utf8");
  } catch (error) {
    errors.push(`${file}: could not read file: ${error.message}`);
    continue;
  }

  const tags = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
  let match;
  let index = 0;

  while ((match = tags.exec(html)) !== null) {
    index += 1;
    const attributes = match[1] || "";
    const body = match[2] || "";
    if (/\bsrc\s*=/i.test(attributes) || !body.trim()) continue;

    const typeMatch = attributes.match(/\btype\s*=\s*["']([^"']+)["']/i);
    const type = (typeMatch?.[1] || "text/javascript").toLowerCase();
    if (!["text/javascript", "application/javascript", "text/ecmascript", "application/ecmascript", "module"].includes(type)) continue;

    try {
      new Script(body, { filename: `${file}#inline-script-${index}` });
      checked += 1;
    } catch (error) {
      errors.push(`${file} inline script ${index}: ${error.message}`);
    }
  }
}

for (const file of jsFiles) {
  try {
    new Script(readFileSync(file, "utf8"), { filename: file });
    checked += 1;
  } catch (error) {
    errors.push(`${file}: ${error.message}`);
  }
}

if (errors.length) {
  console.error("JavaScript syntax check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exitCode = 1;
} else {
  console.log(`JavaScript syntax OK: ${checked} inline/external scripts checked.`);
}
