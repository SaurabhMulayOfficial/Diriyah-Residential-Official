const fs = require("fs");
const path = require("path");
const xml2js = require("xml2js");

const parser = new xml2js.Parser();
const builder = new xml2js.Builder({ xmldec: true });

const PERMSET_DIR = "force-app/main/default/permissionsets";

const fields = JSON.parse(process.env.FIELDS); 
const permsets = process.env.PERMSETS.split(",");

async function processFile(filePath) {
  const xml = fs.readFileSync(filePath, "utf-8");
  const result = await parser.parseStringPromise(xml);

  const ps = result.PermissionSet;

  if (!ps.fieldPermissions) {
    ps.fieldPermissions = [];
  }

  fields.forEach(f => {
    const exists = ps.fieldPermissions.some(fp => fp.field[0] === f.field);

    if (!exists) {
      ps.fieldPermissions.push({
        field: [f.field],
        readable: [String(f.read)],
        editable: [String(f.write)]
      });
    }
  });

  const updatedXml = builder.buildObject(result);
  fs.writeFileSync(filePath, updatedXml);
}

async function run() {
  for (const psName of permsets) {
    const filePath = path.join(PERMSET_DIR, `${psName}.permissionset-meta.xml`);

    if (!fs.existsSync(filePath)) {
      console.log(`❌ Not found: ${psName}`);
      continue;
    }

    console.log(`✅ Updating: ${psName}`);
    await processFile(filePath);
  }
}

run();
