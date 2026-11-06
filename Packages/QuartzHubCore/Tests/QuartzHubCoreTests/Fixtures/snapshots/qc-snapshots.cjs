// QuartzControl's snapshotService.ts as a command, bundled by scripts/snapshots-golden.mjs. Do not edit.

// electron/main/services/snapshotService.ts
var import_fs2 = require("fs");
var import_promises2 = require("fs/promises");
var import_path3 = require("path");
var import_crypto = require("crypto");
var import_child_process2 = require("child_process");

// electron/main/services/runCommand.ts
var import_child_process = require("child_process");

// stub:../i18n
function mainT(key, args2) {
  return JSON.stringify({ key, args: args2 ?? {} });
}

// electron/main/services/runCommand.ts
function needsShell(command) {
  if (process.platform !== "win32") return false;
  return command !== "git";
}
function runCommand(command, args2, cwd, env, timeoutMs) {
  return new Promise((resolvePromise) => {
    const child = (0, import_child_process.spawn)(command, args2, {
      cwd,
      shell: needsShell(command),
      stdio: ["ignore", "pipe", "pipe"],
      ...env ? { env: { ...process.env, ...env } } : {}
    });
    let output = "";
    let stdout = "";
    let settled = false;
    let timer = null;
    const settle = (result) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      resolvePromise(result);
    };
    if (timeoutMs) {
      timer = setTimeout(() => {
        settle({ success: false, stdout, output: `${output}
${mainT("commandTimeout", { ms: timeoutMs, command: `${command} ${args2[0] ?? ""}` })}` });
        child.kill("SIGTERM");
        setTimeout(() => child.kill("SIGKILL"), 2e3).unref();
      }, timeoutMs);
      timer.unref();
    }
    child.stdout?.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      stdout += text;
    });
    child.stderr?.on("data", (chunk) => output += chunk.toString());
    child.on("close", (code) => settle({ success: code === 0, output, stdout }));
    child.on("error", (err) => settle({ success: false, output: String(err), stdout }));
  });
}

// stub:./runCommand
async function runCommand2(command, args2, cwd, env, timeoutMs) {
  return command === "npm" ? { success: true, output: "", stdout: "" } : runCommand(command, args2, cwd, env, timeoutMs);
}

// electron/main/services/projectDirs.ts
var import_fs = require("fs");
var import_path = require("path");
var DIR_NAME = ".quartz-gui";
var IGNORE_LINE = `${DIR_NAME}/`;
function ensureIgnored(projectPath) {
  if (!(0, import_fs.existsSync)((0, import_path.join)(projectPath, ".git"))) return;
  const path = (0, import_path.join)(projectPath, ".gitignore");
  const existing = (0, import_fs.existsSync)(path) ? (0, import_fs.readFileSync)(path, "utf-8") : "";
  const alreadyIgnored = existing.split("\n").map((line) => line.trim()).some((line) => line === IGNORE_LINE || line === DIR_NAME);
  if (alreadyIgnored) return;
  const prefix = existing.length > 0 && !existing.endsWith("\n") ? "\n" : "";
  const block = `${prefix}
# ${mainT("gitignoreComment")}
${IGNORE_LINE}
`;
  (0, import_fs.writeFileSync)(path, existing + block, "utf-8");
}
function quartzGuiDir(projectPath, ...sub) {
  const dir = (0, import_path.join)(projectPath, DIR_NAME, ...sub);
  if (!(0, import_fs.existsSync)(dir)) (0, import_fs.mkdirSync)(dir, { recursive: true });
  ensureIgnored(projectPath);
  return dir;
}
function quartzGuiPath(projectPath, ...sub) {
  return (0, import_path.join)(projectPath, DIR_NAME, ...sub);
}

// electron/main/services/contentSymlink.ts
var import_promises = require("fs/promises");
var import_path2 = require("path");
async function withContentSymlinkParked(projectPath, fn) {
  const contentPath = (0, import_path2.join)(projectPath, "content");
  let target = null;
  try {
    const stat = await (0, import_promises.lstat)(contentPath);
    if (stat.isSymbolicLink()) target = await (0, import_promises.readlink)(contentPath);
  } catch {
  }
  if (target === null) return fn();
  await (0, import_promises.rm)(contentPath);
  try {
    return await fn();
  } finally {
    await (0, import_promises.rm)(contentPath, { recursive: true, force: true });
    await (0, import_promises.symlink)(target, contentPath, "dir");
  }
}

// stub:./projectPaths
async function repointAuthoredFrames() {
}

// electron/main/services/snapshotService.ts
var STORE_DIR = "snapshots.git";
var REF_PREFIX = "refs/snapshots/";
var SETTINGS_FILE = "snapshot-settings.json";
var NUL = "\0";
var COALESCE_WINDOW = 15 * 60 * 1e3;
var COALESCING_KINDS = /* @__PURE__ */ new Set(["configChange"]);
var KEPT_KINDS = /* @__PURE__ */ new Set(["manual", "styleMigration"]);
var queues = /* @__PURE__ */ new Map();
function serialize(projectPath, operation) {
  const previous = queues.get(projectPath) ?? Promise.resolve();
  const next = previous.then(operation, operation);
  queues.set(
    projectPath,
    next.catch(() => void 0)
  );
  return next;
}
function storePath(projectPath) {
  return quartzGuiPath(projectPath, STORE_DIR);
}
function git(projectPath, args2, env) {
  return runCommand2("git", ["--git-dir", storePath(projectPath), "--work-tree", projectPath, ...args2], projectPath, env);
}
var BASE_EXCLUDES = [
  "/node_modules/",
  "/public/",
  "/prof/",
  "/.quartz/",
  "/.quartz-cache/",
  "/.turbo/",
  "/.git/",
  "/.quartz-gui/",
  "/tsconfig.tsbuildinfo",
  ".DS_Store"
];
function isSnapshotWorthy(entryName) {
  if (entryName === STORE_DIR || entryName === SETTINGS_FILE) return false;
  if (entryName === "backups" || entryName === "content-backups") return false;
  if (entryName === "logs") return false;
  if (entryName === "staging") return false;
  return !entryName.startsWith("deploy-manifest-");
}
async function writeExcludes(projectPath, settings) {
  const lines = [...BASE_EXCLUDES];
  if (!settings.includeContent) lines.push("/content/");
  const infoDir = (0, import_path3.join)(storePath(projectPath), "info");
  await (0, import_promises2.mkdir)(infoDir, { recursive: true });
  await (0, import_promises2.writeFile)((0, import_path3.join)(infoDir, "exclude"), `${lines.join("\n")}
`, "utf-8");
}
async function ensureStore(projectPath) {
  const store = storePath(projectPath);
  if (!(0, import_fs2.existsSync)((0, import_path3.join)(store, "HEAD"))) {
    quartzGuiDir(projectPath);
    await runCommand2("git", ["init", "--bare", "--quiet", store]);
    await runCommand2("git", ["--git-dir", store, "config", "core.bare", "false"]);
    await runCommand2("git", ["--git-dir", store, "config", "user.name", "QuartzControl"]);
    await runCommand2("git", ["--git-dir", store, "config", "user.email", "snapshots@quartzcontrol.local"]);
  }
  const settings = await getSettings(projectPath);
  await writeExcludes(projectPath, settings);
  return settings;
}
async function stage(projectPath, settings) {
  const added = await git(projectPath, ["add", "-A"]);
  if (!added.success) throw new Error(`${mainT("snapshotStageFailed")}
${added.output}`);
  const entries = (await (0, import_promises2.readdir)(quartzGuiPath(projectPath))).filter(isSnapshotWorthy).map((name) => `.quartz-gui/${name}`);
  if (entries.length > 0) await git(projectPath, ["add", "-f", "--", ...entries]);
  if (!settings.includeContent) {
    await git(projectPath, ["rm", "-r", "--cached", "--quiet", "--ignore-unmatch", "--", "content"]);
  }
}
async function getSettings(projectPath) {
  let contentExists = false;
  let contentIsSymlink = false;
  try {
    const stat = await (0, import_promises2.lstat)((0, import_path3.join)(projectPath, "content"));
    contentExists = true;
    contentIsSymlink = stat.isSymbolicLink();
  } catch {
  }
  let stored = {};
  try {
    stored = JSON.parse(await (0, import_promises2.readFile)(quartzGuiPath(projectPath, SETTINGS_FILE), "utf-8"));
  } catch {
  }
  return {
    includeContent: contentIsSymlink ? false : stored.includeContent ?? contentExists,
    contentExists,
    contentIsSymlink
  };
}
async function saveSettingsUnlocked(projectPath, includeContent) {
  const { contentIsSymlink } = await getSettings(projectPath);
  await (0, import_promises2.writeFile)(
    (0, import_path3.join)(quartzGuiDir(projectPath), SETTINGS_FILE),
    JSON.stringify({ includeContent: contentIsSymlink ? false : includeContent }, null, 2),
    "utf-8"
  );
  const settings = await getSettings(projectPath);
  await writeExcludes(projectPath, settings);
  return settings;
}
function newSnapshotId() {
  return `${(/* @__PURE__ */ new Date()).toISOString().replace(/[:.]/g, "-")}-${(0, import_crypto.randomBytes)(2).toString("hex")}`;
}
async function createSnapshotUnlocked(projectPath, kind, rawLabel = "") {
  const label = rawLabel.replace(/\s+/g, " ").trim().slice(0, 120);
  const settings = await ensureStore(projectPath);
  await stage(projectPath, settings);
  const tree = (await git(projectPath, ["write-tree"])).output.trim();
  if (!tree) throw new Error(mainT("snapshotWriteTreeFailed"));
  if (!KEPT_KINDS.has(kind)) {
    const existing = await listSnapshots(projectPath);
    const [newest] = existing;
    if (newest) {
      const previousTree = (await git(projectPath, ["rev-parse", `${newest.commit}^{tree}`])).output.trim();
      if (previousTree === tree) return null;
    }
    if (COALESCING_KINDS.has(kind)) {
      const recent = existing.find(
        (entry) => entry.kind === kind && Date.now() - new Date(entry.createdAt).getTime() < COALESCE_WINDOW
      );
      if (recent) return null;
    }
  }
  const head = (await runCommand2("git", ["rev-parse", "HEAD"], projectPath)).output.trim();
  const subject = `${kind} ${head || "-"}${label ? ` ${label}` : ""}`;
  const commit = (await git(projectPath, ["commit-tree", tree, "-m", subject])).output.trim();
  const id = newSnapshotId();
  await git(projectPath, ["update-ref", `${REF_PREFIX}${id}`, commit]);
  await git(projectPath, ["gc", "--auto", "--quiet"]);
  if (!KEPT_KINDS.has(kind)) await pruneAutomaticUnlocked(projectPath);
  return { id, commit, createdAt: (/* @__PURE__ */ new Date()).toISOString(), kind, label, projectHead: head || void 0 };
}
async function listSnapshots(projectPath) {
  if (!(0, import_fs2.existsSync)((0, import_path3.join)(storePath(projectPath), "HEAD"))) return [];
  const format = ["%(refname)", "%(objectname)", "%(creatordate:iso-strict)", "%(subject)"].join(" ");
  const result = await git(projectPath, ["for-each-ref", `--format=${format}`, REF_PREFIX]);
  if (!result.success) return [];
  return result.output.split("\n").map((line) => line.trim()).filter((line) => line.startsWith(REF_PREFIX)).map((line) => {
    const [refname, commit, createdAt, kind, projectHead, ...rest] = line.split(" ");
    return {
      id: refname.slice(REF_PREFIX.length),
      commit,
      createdAt,
      projectHead: projectHead && projectHead !== "-" ? projectHead : void 0,
      kind: kind || "manual",
      label: rest.join(" ")
    };
  }).sort((a, b) => b.id.localeCompare(a.id));
}
function isPartial(kind) {
  return kind === "imported";
}
async function snapshotPaths(projectPath, commit) {
  return (await git(projectPath, ["ls-tree", "-r", "--name-only", "-z", commit])).output.split(NUL).filter(Boolean);
}
async function findSnapshot(projectPath, id) {
  return (await listSnapshots(projectPath)).find((entry) => entry.id === id);
}
async function commitFor(projectPath, id) {
  const result = await git(projectPath, ["rev-parse", `${REF_PREFIX}${id}`]);
  const commit = result.output.trim();
  if (!result.success || !commit) throw new Error(mainT("snapshotMissing", { id }));
  return commit;
}
async function migrateConfigBackupsUnlocked(projectPath) {
  const legacyDir = (0, import_path3.join)(projectPath, ".quartz-gui", "backups");
  const claimedDir = `${legacyDir}.migrated`;
  try {
    await (0, import_promises2.rename)(legacyDir, claimedDir);
  } catch {
    return 0;
  }
  await ensureStore(projectPath);
  const files = (await (0, import_promises2.readdir)(claimedDir)).filter((name) => /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z\.yaml$/.test(name)).sort();
  let imported = 0;
  for (const file of files) {
    const id = file.replace(/\.yaml$/, "");
    const blob = (await runCommand2("git", ["--git-dir", storePath(projectPath), "hash-object", "-w", (0, import_path3.join)(claimedDir, file)], projectPath)).output.trim();
    if (!blob) continue;
    const tree = (await runWithInput(
      ["--git-dir", storePath(projectPath), "mktree"],
      `100644 blob ${blob}	quartz.config.yaml
`,
      projectPath
    )).trim();
    if (!tree) continue;
    const when = idToIsoDate(id);
    const commit = (await git(
      projectPath,
      ["commit-tree", tree, "-m", "imported -"],
      when ? { GIT_AUTHOR_DATE: when, GIT_COMMITTER_DATE: when } : void 0
    )).output.trim();
    if (!commit) continue;
    await git(projectPath, ["update-ref", `${REF_PREFIX}${id}-0000`, commit]);
    imported += 1;
  }
  await pruneAutomaticUnlocked(projectPath);
  return imported;
}
function idToIsoDate(id) {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2})-(\d{2})-(\d{2})-(\d{3})Z$/.exec(id);
  return match ? `${match[1]}:${match[2]}:${match[3]}.${match[4]}Z` : null;
}
function runWithInput(args2, input, cwd) {
  return new Promise((resolvePromise) => {
    const child = (0, import_child_process2.spawn)("git", args2, { cwd, stdio: ["pipe", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk) => output += chunk.toString());
    child.on("close", () => resolvePromise(output));
    child.on("error", () => resolvePromise(""));
    child.stdin.end(input);
  });
}
async function diffSnapshotUnlocked(projectPath, id) {
  const commit = await commitFor(projectPath, id);
  const snapshot = await findSnapshot(projectPath, id);
  await stage(projectPath, await ensureStore(projectPath));
  const limitTo = snapshot && isPartial(snapshot.kind) ? ["--", ...await snapshotPaths(projectPath, commit)] : [];
  const result = await git(projectPath, ["diff-index", "--cached", "--name-status", "-z", commit, ...limitTo]);
  if (!result.success) return [];
  const parts = result.output.split(NUL).filter((part) => part.length > 0);
  const changes = [];
  for (let i = 0; i + 1 < parts.length; i += 2) {
    const letter = parts[i][0];
    changes.push({
      path: parts[i + 1],
      status: letter === "A" ? "addedSince" : letter === "D" ? "removedSince" : "modified"
    });
  }
  return changes.sort((a, b) => a.path.localeCompare(b.path));
}
async function fileDiffUnlocked(projectPath, id, path) {
  const commit = await commitFor(projectPath, id);
  await stage(projectPath, await ensureStore(projectPath));
  return (await git(projectPath, ["diff", "--cached", commit, "--", path])).output;
}
var PATH_BATCH = 1e3;
function inBatches(paths) {
  const batches = [];
  for (let i = 0; i < paths.length; i += PATH_BATCH) batches.push(paths.slice(i, i + PATH_BATCH));
  return batches;
}
async function restoreSnapshotUnlocked(projectPath, id, options = {}) {
  const { paths, resetProjectHead } = options;
  const commit = await commitFor(projectPath, id);
  const snapshot = await findSnapshot(projectPath, id);
  const effectivePaths = paths && paths.length > 0 ? paths : snapshot && isPartial(snapshot.kind) ? await snapshotPaths(projectPath, commit) : void 0;
  const touched = effectivePaths ?? (await diffSnapshotUnlocked(projectPath, id)).map((change) => change.path);
  const settings = await getSettings(projectPath);
  await createSnapshotUnlocked(projectPath, "restore", "");
  await stage(projectPath, settings);
  const output = [];
  const touchesContent = touched.some((path) => path === "content" || path.startsWith("content/"));
  const needsParking = resetProjectHead || touchesContent;
  const park = (fn) => needsParking ? withContentSymlinkParked(projectPath, fn) : fn();
  const failure = await park(async () => {
    if (resetProjectHead && snapshot?.projectHead) {
      const reset = await runCommand2("git", ["reset", "--hard", snapshot.projectHead], projectPath);
      if (!reset.success) return { success: false, output: reset.output };
      output.push(reset.output);
    }
    if (!effectivePaths) {
      const read = await git(projectPath, ["read-tree", "-u", "--reset", commit]);
      if (!read.success) return { success: false, output: read.output };
      output.push(read.output);
      return null;
    }
    const inSnapshot = new Set(
      (await git(projectPath, ["ls-tree", "-r", "--name-only", "-z", commit])).output.split(NUL).filter(Boolean)
    );
    const toRestore = effectivePaths.filter((path) => inSnapshot.has(path));
    const toDelete = effectivePaths.filter((path) => !inSnapshot.has(path));
    for (const batch of inBatches(toRestore)) {
      const checkout = await git(projectPath, ["checkout", commit, "--", ...batch]);
      if (!checkout.success) return { success: false, output: checkout.output };
      output.push(checkout.output);
    }
    for (const doomedPath of toDelete) await (0, import_promises2.rm)((0, import_path3.join)(projectPath, doomedPath), { force: true });
    for (const batch of inBatches(toDelete)) {
      await git(projectPath, ["rm", "--cached", "--quiet", "--", ...batch]);
    }
    return null;
  });
  if (failure) return failure;
  if (settings.contentIsSymlink && touchesContent) {
    output.push(
      mainT("snapshotVaultUntouched")
    );
  }
  if (touched.some((path) => path === "quartz.config.yaml" || path === "quartz.lock.json")) {
    await repointAuthoredFrames(projectPath);
  }
  if (touched.some((path) => path === "package.json" || path === "package-lock.json")) {
    const install = await runCommand2("npm", ["install"], projectPath);
    output.push(install.output);
    if (!install.success) return { success: false, output: output.join("\n") };
  }
  return { success: true, output: output.join("\n").trim() };
}
async function deleteSnapshotUnlocked(projectPath, id) {
  await git(projectPath, ["update-ref", "-d", `${REF_PREFIX}${id}`]);
  await git(projectPath, ["gc", "--prune=now", "--quiet"]);
}
async function exportSnapshotUnlocked(projectPath, id, targetFile) {
  const commit = await commitFor(projectPath, id);
  const result = await git(projectPath, ["archive", "--format=zip", `--prefix=${id}/`, "-o", targetFile, commit]);
  if (!result.success) throw new Error(result.output);
}
var DAY = 24 * 60 * 60 * 1e3;
function retentionBucket(age, createdAt) {
  if (age < DAY) return null;
  if (age < 7 * DAY) return `day-${createdAt.toISOString().slice(0, 10)}`;
  if (age < 56 * DAY) return `week-${Math.floor(createdAt.getTime() / (7 * DAY))}`;
  return `month-${createdAt.toISOString().slice(0, 7)}`;
}
async function pruneAutomaticUnlocked(projectPath) {
  const snapshots = await listSnapshots(projectPath);
  const now = Date.now();
  const kept = /* @__PURE__ */ new Set();
  const doomed = [];
  for (const snapshot of snapshots) {
    if (KEPT_KINDS.has(snapshot.kind)) continue;
    const createdAt = new Date(snapshot.createdAt);
    const bucket = retentionBucket(now - createdAt.getTime(), createdAt);
    if (bucket === null) continue;
    if (kept.has(bucket)) doomed.push(snapshot.id);
    else kept.add(bucket);
  }
  for (const id of doomed) await git(projectPath, ["update-ref", "-d", `${REF_PREFIX}${id}`]);
  if (doomed.length > 0) await git(projectPath, ["gc", "--prune=now", "--quiet"]);
  return doomed.length;
}
var createSnapshot = (projectPath, kind, label = "") => serialize(projectPath, () => createSnapshotUnlocked(projectPath, kind, label));
var diffSnapshot = (projectPath, id) => serialize(projectPath, () => diffSnapshotUnlocked(projectPath, id));
var fileDiff = (projectPath, id, path) => serialize(projectPath, () => fileDiffUnlocked(projectPath, id, path));
var restoreSnapshot = (projectPath, id, options = {}) => serialize(projectPath, () => restoreSnapshotUnlocked(projectPath, id, options));
var deleteSnapshot = (projectPath, id) => serialize(projectPath, () => deleteSnapshotUnlocked(projectPath, id));
var exportSnapshot = (projectPath, id, targetFile) => serialize(projectPath, () => exportSnapshotUnlocked(projectPath, id, targetFile));
var saveSettings = (projectPath, includeContent) => serialize(projectPath, () => saveSettingsUnlocked(projectPath, includeContent));
var migrateConfigBackups = (projectPath) => serialize(projectPath, () => migrateConfigBackupsUnlocked(projectPath));
var pruneAutomatic = (projectPath) => serialize(projectPath, () => pruneAutomaticUnlocked(projectPath));

// qc-snapshots-entry.ts
var [op, project, raw] = process.argv.slice(2);
var args = raw ? JSON.parse(raw) : [];
var ops = { list: listSnapshots, settings: getSettings, saveSettings, create: createSnapshot, diff: diffSnapshot, fileDiff, restore: restoreSnapshot, delete: deleteSnapshot, export: exportSnapshot, migrate: migrateConfigBackups, prune: pruneAutomatic };
ops[op](project, ...args).then((result) => process.stdout.write(JSON.stringify({ result: result ?? null })), (e) => process.stdout.write(JSON.stringify({ error: e.message })));
