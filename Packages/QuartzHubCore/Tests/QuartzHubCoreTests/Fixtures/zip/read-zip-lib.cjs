var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// electron/main/services/zipArchive.ts
var zipArchive_exports = {};
__export(zipArchive_exports, {
  createZip: () => createZip,
  readZip: () => readZip,
  readZipFile: () => readZipFile,
  writeZipFile: () => writeZipFile
});
module.exports = __toCommonJS(zipArchive_exports);
var import_zlib = require("zlib");
var import_fs = require("fs");
var import_promises = require("fs/promises");

// stub:i18n
function mainT(key, args) {
  return JSON.stringify({ key, args: args ?? {} });
}

// electron/main/services/zipArchive.ts
var LOCAL_SIG = 67324752;
var CENTRAL_SIG = 33639248;
var EOCD_SIG = 101010256;
var FLAG_UTF8 = 2048;
var METHOD_DEFLATE = 8;
var METHOD_STORE = 0;
var MAX_SIZE = 4294967295;
function dosDateTime(date) {
  const year = Math.min(Math.max(date.getFullYear(), 1980), 2107);
  return {
    time: date.getHours() << 11 | date.getMinutes() << 5 | Math.floor(date.getSeconds() / 2),
    date: year - 1980 << 9 | date.getMonth() + 1 << 5 | date.getDate()
  };
}
function isSafeEntryName(name) {
  if (name === "" || name.startsWith("/") || name.includes("\0") || /^[a-zA-Z]:/.test(name)) return false;
  return !name.split(/[/\\]/).some((segment) => segment === "..");
}
function createZip(entries, modified = /* @__PURE__ */ new Date()) {
  const { time, date } = dosDateTime(modified);
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, "utf-8");
    const deflated = (0, import_zlib.deflateRawSync)(entry.data);
    const useDeflate = !entry.store && deflated.length < entry.data.length;
    const body = useDeflate ? deflated : entry.data;
    const method = useDeflate ? METHOD_DEFLATE : METHOD_STORE;
    if (entry.data.length > MAX_SIZE || body.length > MAX_SIZE) {
      throw new Error(mainT("zipEntryTooLarge", { name: entry.name }));
    }
    const checksum = (0, import_zlib.crc32)(entry.data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(LOCAL_SIG, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(FLAG_UTF8, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(time, 10);
    local.writeUInt16LE(date, 12);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(entry.data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, body);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(CENTRAL_SIG, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(FLAG_UTF8, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(time, 12);
    central.writeUInt16LE(date, 14);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(33188 << 16 >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += local.length + name.length + body.length;
  }
  const centralBuffer = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(EOCD_SIG, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralBuffer.length, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(0, 20);
  return Buffer.concat([...locals, centralBuffer, eocd]);
}
var MAX_UNPACKED_BYTES = 256 * 1024 * 1024;
function readZip(buffer) {
  const minStart = Math.max(0, buffer.length - 22 - 65535);
  let eocd = -1;
  for (let i = buffer.length - 22; i >= minStart; i--) {
    if (buffer.readUInt32LE(i) === EOCD_SIG) {
      eocd = i;
      break;
    }
  }
  if (eocd === -1) throw new Error(mainT("zipNotAPackage"));
  const count = buffer.readUInt16LE(eocd + 10);
  let cursor = buffer.readUInt32LE(eocd + 16);
  const files = /* @__PURE__ */ new Map();
  let unpacked = 0;
  for (let i = 0; i < count; i++) {
    if (buffer.readUInt32LE(cursor) !== CENTRAL_SIG) throw new Error(mainT("zipBadDirectory"));
    const method = buffer.readUInt16LE(cursor + 10);
    const expectedCrc = buffer.readUInt32LE(cursor + 16);
    const compressedSize = buffer.readUInt32LE(cursor + 20);
    const uncompressedSize = buffer.readUInt32LE(cursor + 24);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const localOffset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.toString("utf-8", cursor + 46, cursor + 46 + nameLength);
    cursor += 46 + nameLength + extraLength + commentLength;
    if (name.endsWith("/")) continue;
    if (!isSafeEntryName(name)) throw new Error(mainT("zipEntryUnsafeName", { name }));
    if (buffer.readUInt32LE(localOffset) !== LOCAL_SIG) throw new Error(mainT("zipBadHeader"));
    const localNameLength = buffer.readUInt16LE(localOffset + 26);
    const localExtraLength = buffer.readUInt16LE(localOffset + 28);
    const start = localOffset + 30 + localNameLength + localExtraLength;
    const body = buffer.subarray(start, start + compressedSize);
    unpacked += uncompressedSize;
    if (unpacked > MAX_UNPACKED_BYTES) {
      throw new Error(mainT("zipTooLarge", { limit: Math.round(MAX_UNPACKED_BYTES / 1024 / 1024) }));
    }
    let data;
    if (method === METHOD_STORE) data = Buffer.from(body);
    else if (method === METHOD_DEFLATE) {
      if (uncompressedSize === 0) data = Buffer.alloc(0);
      else {
        try {
          data = (0, import_zlib.inflateRawSync)(body, { maxOutputLength: uncompressedSize });
        } catch {
          throw new Error(mainT("zipEntryCorrupt", { name }));
        }
      }
    } else throw new Error(mainT("zipUnsupportedMethod", { method }));
    if (data.length !== uncompressedSize || (0, import_zlib.crc32)(data) !== expectedCrc) {
      throw new Error(mainT("zipEntryCorrupt", { name }));
    }
    files.set(name, data);
  }
  return files;
}
async function writeZipFile(path, entries) {
  await (0, import_promises.writeFile)(path, createZip(entries));
}
async function readZipFile(path) {
  if (!(0, import_fs.existsSync)(path)) throw new Error(mainT("zipFileMissing"));
  return readZip(await (0, import_promises.readFile)(path));
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  createZip,
  readZip,
  readZipFile,
  writeZipFile
});
