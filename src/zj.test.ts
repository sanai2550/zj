import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { directoryCommand, jumpCandidates, zjQuery, discoverDirectories, isDescendant, navigationMatches } from "./zj.ts";
import { mkdtempSync, mkdirSync, symlinkSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { buildRequest } from "./suggest.ts";

test("zj trigger matches a command boundary and strips the trigger", () => {
  assert.equal(zjQuery("zj"), "");
  assert.equal(zjQuery("zj   payments backend  "), "payments backend");
  assert.equal(zjQuery("zjobs"), undefined);
  assert.equal(zjQuery("echo zj"), undefined);
});

test("explicit navigation prefers all requested folder words over a partial match", () => {
  const root = "/home/ducdv/lazycy_project";
  const target = `${root}/payslip/java-payslip-aimexy`;
  assert.deepEqual(navigationMatches("go to java payslip aimexy", [
    `${root}/java-aimexy-sp`, target, `${root}/payslip/react-keycloakify-lazycy`,
  ], root), [target]);
  assert.deepEqual(navigationMatches("show java errors", [target], root), []);
  assert.deepEqual(navigationMatches("go to missing project", [target], root), []);
});

test("directory paths remain literal shell arguments", () => {
  const path = "/tmp/a'b $(echo unexpected); space";
  const command = directoryCommand(path).replace(/^cd -- /, "printf '%s' ");
  assert.equal(execFileSync("zsh", ["-fc", command], { encoding: "utf8" }), path);
});

test("combine history and directories, deduplicate and exclude previous triggers", () => {
  assert.deepEqual(jumpCandidates(["git status", "zj status", "cd -- '/work'"], ["/work", "/other", "relative"]),
    ["git status", "cd -- '/work'", "cd -- '/other'"]);
});

test("intent mode uses a different decision request from literal completion", () => {
  const candidates = [{ id: "C00", command: "git status" }];
  assert.notDeepEqual(buildRequest("check changes", candidates, true).questions,
    buildRequest("check changes", candidates).questions);
});

test("discovers unvisited descendants, skips dependencies and symlink escapes, and bounds results", () => {
  const root = mkdtempSync(join(tmpdir(), "zj-discovery-"));
  try {
    for (const path of ["app/src", ".git/objects", "node_modules/pkg", "other"]) {
      mkdirSync(join(root, path), { recursive: true });
    }
    symlinkSync("/", join(root, "escape"));
    assert.deepEqual(discoverDirectories(root, 100), [join(root, "app"), join(root, "other"), join(root, "app/src")]);
    assert.equal(discoverDirectories(root, 1).length, 1);
    assert.equal(discoverDirectories(root, 0).length, 0);
    assert.equal(isDescendant(root, `${root}-sibling/app`), false);
    assert.equal(isDescendant(root, root), false);
    assert.equal(isDescendant(root, join(root, "app")), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
