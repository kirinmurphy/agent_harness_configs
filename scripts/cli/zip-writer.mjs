import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return (~c) >>> 0;
}

function dosDateTime(d = new Date()) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return { time: time & 0xffff, date: date & 0xffff };
}

function collectFiles(dir, baseInZip) {
  const out = [];
  const walk = (cur, rel) => {
    for (const ent of fs.readdirSync(cur, { withFileTypes: true })) {
      const full = path.join(cur, ent.name);
      const zipRel = rel ? `${rel}/${ent.name}` : ent.name;
      if (ent.isDirectory()) walk(full, zipRel);
      else if (ent.isFile()) out.push({ name: `${baseInZip}/${zipRel}`, data: fs.readFileSync(full) });
    }
  };
  walk(dir, "");
  return out;
}

export function writeZip(zipPath, entries) {
  const files = [];
  for (const e of entries) files.push(...collectFiles(e.srcDir, e.nameInZip));

  const { time, date } = dosDateTime();
  const localParts = [];
  const central = [];
  let offset = 0;

  for (const f of files) {
    const nameBuf = Buffer.from(f.name, "utf8");
    const crc = crc32(f.data);
    const deflated = zlib.deflateRawSync(f.data);
    const useDeflate = deflated.length < f.data.length;
    const stored = useDeflate ? deflated : f.data;
    const method = useDeflate ? 8 : 0;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(time, 10);
    local.writeUInt16LE(date, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(stored.length, 18);
    local.writeUInt32LE(f.data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    localParts.push(local, nameBuf, stored);

    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4);
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(0, 8);
    cen.writeUInt16LE(method, 10);
    cen.writeUInt16LE(time, 12);
    cen.writeUInt16LE(date, 14);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(stored.length, 20);
    cen.writeUInt32LE(f.data.length, 24);
    cen.writeUInt16LE(nameBuf.length, 28);
    cen.writeUInt32LE(offset, 42);
    central.push(cen, nameBuf);

    offset += local.length + nameBuf.length + stored.length;
  }

  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);

  fs.writeFileSync(zipPath, Buffer.concat([...localParts, centralBuf, end]));
  return zipPath;
}
