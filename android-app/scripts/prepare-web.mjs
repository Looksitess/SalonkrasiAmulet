import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("../../", import.meta.url);
const out = join(root.pathname, "www");
const base = "https://raw.githubusercontent.com/Looksitess/SalonkrasiAmulet/main/admin";
const assets = [
  ["index.html", "index.html"],
  ["manifest.webmanifest", "manifest.webmanifest"],
  ["sw.js", "sw.js"],
  ["app-icon.svg", "app-icon.svg"],
  ["android-icon-192.png", "android-icon-192.png"],
  ["android-icon-512.png", "android-icon-512.png"]
];

await mkdir(out, { recursive: true });

for (const [source, destination] of assets) {
  const response = await fetch(base + "/" + source, { redirect: "follow" });
  if (!response.ok) {
    throw new Error("Could not download admin/" + source + ": HTTP " + response.status);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length === 0) throw new Error("Empty admin asset: " + source);
  await writeFile(join(out, destination), bytes);
  console.log("Prepared " + destination + " (" + bytes.length + " bytes)");
}

const html = await (await import("node:fs/promises")).readFile(join(out, "index.html"), "utf8");
for (const required of ['id="loginScreen"', "supabaseClient", "id=\"adminScreen\""]) {
  if (!html.includes(required)) throw new Error("Downloaded admin page is missing expected content: " + required);
}
console.log("Admin web app prepared successfully.");
