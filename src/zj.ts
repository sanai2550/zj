import { execFileSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join, relative, isAbsolute, resolve } from "node:path";

/** Quote a literal path for zsh; never interpret directory names as shell code. */
export function directoryCommand(path: string): string {
  return `cd -- '${path.replaceAll("'", "'\\''")}'`;
}

export function zjQuery(buffer: string): string | undefined {
  const match = /^zj(?:\s+([\s\S]*))?$/.exec(buffer);
  return match ? (match[1] ?? "").trim() : undefined;
}

export function jumpCandidates(history: string[], directories: string[]): string[] {
  return [...new Set([
    ...history.filter(command => zjQuery(command) === undefined),
    ...directories.filter(path => path.startsWith("/")).map(directoryCommand),
  ])];
}

export function navigationMatches(query: string, directories: string[], root = process.cwd()): string[] {
  const match = /^(?:go\s+to|cd|jump\s+to|navigate\s+to)\s+(.+)$/i.exec(query.trim());
  if (!match) return [];
  const words = match[1]!.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
  if (!words.length) return [];
  return directories.filter(path => {
    const parts = new Set(relative(root, path).toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []);
    return words.every(word => parts.has(word));
  });
}

export function isDescendant(root: string, path: string): boolean {
  const rel = relative(root, path);
  return rel !== "" && rel !== ".." && !rel.startsWith("../") && !isAbsolute(rel);
}

/** Bounded breadth-first discovery: shallow project folders come first. */
export function discoverDirectories(root: string, limit: number): string[] {
  const ignored = new Set(["node_modules", "vendor", "dist", "build", "target", "__pycache__"]);
  const queue = [{ path: resolve(root), depth: 0 }];
  const found: string[] = [];
  const deadline = Date.now() + 150;
  for (let i = 0; i < queue.length && found.length < limit && Date.now() < deadline; i++) {
    const current = queue[i]!;
    if (current.depth >= 4) continue;
    try {
      const entries = readdirSync(current.path, { withFileTypes: true })
        .sort((a, b) => a.name.localeCompare(b.name));
      for (const entry of entries) {
        // Do not follow symlinks: a link may point outside the current folder.
        if (!entry.isDirectory() || entry.name.startsWith(".") || ignored.has(entry.name)) continue;
        const path = join(current.path, entry.name);
        found.push(path);
        queue.push({ path, depth: current.depth + 1 });
        if (found.length >= limit) break;
      }
    } catch { /* Unreadable or removed directory: continue with its siblings. */ }
  }
  return found;
}

export function knownDirectories(limit: number, root = process.cwd()): string[] {
  const discovered = discoverDirectories(root, limit);
  let remembered: string[] = [];
  try {
    // Zoxide returns directories in frecency order. Preserve that ordering as
    // context, but let Jev assign one common probability scale to all choices.
    remembered = execFileSync("zoxide", ["query", "--list"], {
      encoding: "utf8", timeout: 2000, stdio: ["ignore", "pipe", "ignore"],
    }).split("\n").filter(path => isAbsolute(path) && isDescendant(root, path));
  } catch {
    // Filesystem discovery also works before zoxide has learned any paths.
  }
  return [...new Set([...remembered, ...discovered])].slice(0, limit);
}
