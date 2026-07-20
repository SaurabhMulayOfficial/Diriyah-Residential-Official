const fs = require("fs");
const path = require("path");

const ROOT = path.join(
  process.cwd(),
  "force-app",
  "main",
  "default"
);

const OUTPUT = "salesforce_inventory.md";

function getDirectories(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);
}

function getFiles(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter(f => f.isFile())
    .map(f => f.name);
}

let md = "# Salesforce Metadata Inventory\n\n";

for (const metadataFolder of getDirectories(ROOT)) {
  const folderPath = path.join(ROOT, metadataFolder);

  md += `## ${metadataFolder}\n\n`;
  md += "| Component  \n";
  md += "|----------- \n";

  function walk(current) {
    const entries = fs.readdirSync(current, {
      withFileTypes: true,
    });

    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);

      if (entry.isDirectory()) {
        walk(fullPath);
      } else {
        const componentName =
          path.basename(
            entry.name,
            path.extname(entry.name)
          );

        md += `| ${componentName} |\n`;
      }
    }
  }

  walk(folderPath);

  md += "\n\n";
}

fs.writeFileSync(OUTPUT, md);

console.log(`Generated ${OUTPUT}`);