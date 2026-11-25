import { describe, expect, it } from "vite-plus/test";

import {
  CLI_RELEASE_BASE_URL_ENV,
  CLI_RELEASE_REPOSITORY,
  CLI_RELEASES_PAGE_URL,
  SWFT_GITHUB_TOKEN_ENV,
  SWFT_RELEASE_BASE_URL_ENV,
  cliArchiveTarCommand,
  cliReleaseAssetUrl,
  cliReleaseIndexPageUrl,
  newestCliReleaseVersion,
  parseChecksums,
  parseGitHubReleaseDownloadUrl,
} from "./cliRelease.ts";

describe("cliRelease", () => {
  it("parses sha256sum output including binary-mode markers", () => {
    const checksums = parseChecksums(
      [
        `${"a".repeat(64)}  t3-1.2.3-linux-x64.tar.gz`,
        `${"B".repeat(64)} *t3-1.2.3-win32-x64.zip`,
        "not a checksum line",
        "",
      ].join("\n"),
    );
    expect(checksums.get("t3-1.2.3-linux-x64.tar.gz")).toBe("a".repeat(64));
    expect(checksums.get("t3-1.2.3-win32-x64.zip")).toBe("b".repeat(64));
    expect(checksums.size).toBe(2);
  });

  it("extracts with the System32 bsdtar on Windows and plain tar elsewhere", () => {
    expect(cliArchiveTarCommand("linux", {})).toBe("tar");
    expect(cliArchiveTarCommand("win32", { SystemRoot: "D:\\Win" })).toBe(
      "D:\\Win\\System32\\tar.exe",
    );
    expect(cliArchiveTarCommand("win32", {})).toBe("C:\\Windows\\System32\\tar.exe");
  });

  it("picks the newest non-draft release on the requested channel", () => {
    const releases = [
      { tag_name: "v1.2.4-preview.20260912.9", draft: true },
      { tag_name: "v1.2.4-preview.20260912.8" },
      { tag_name: "v1.2.4-nightly.20260912.7" },
      { tag_name: "desktop-preview" },
      { tag_name: "v1.2.3" },
      { tag_name: "v1.2.3-nightly.20260911.2" },
    ];
    expect(newestCliReleaseVersion(releases, "preview")).toBe("1.2.4-preview.20260912.8");
    expect(newestCliReleaseVersion(releases, "nightly")).toBe("1.2.4-nightly.20260912.7");
    expect(newestCliReleaseVersion(releases, "stable")).toBe("1.2.3");
    expect(newestCliReleaseVersion([{ tag_name: "v1.2.3" }], "preview")).toBeUndefined();
  });

  it("targets gojimq/swft and exposes Swft env var names", () => {
    expect(CLI_RELEASE_REPOSITORY).toBe("gojimq/swft");
    expect(CLI_RELEASES_PAGE_URL).toBe("https://github.com/gojimq/swft/releases");
    expect(cliReleaseAssetUrl("0.2.0", "SHA256SUMS")).toBe(
      "https://github.com/gojimq/swft/releases/download/v0.2.0/SHA256SUMS",
    );
    expect(cliReleaseIndexPageUrl(1)).toBe(
      "https://api.github.com/repos/gojimq/swft/releases?per_page=100&page=1",
    );
    expect(CLI_RELEASE_BASE_URL_ENV).toBe("T3CODE_RELEASE_BASE_URL");
    expect(SWFT_RELEASE_BASE_URL_ENV).toBe("SWFT_RELEASE_BASE_URL");
    expect(SWFT_GITHUB_TOKEN_ENV).toBe("SWFT_GITHUB_TOKEN");
  });

  it("parses standard GitHub release download URLs and rejects others", () => {
    expect(
      parseGitHubReleaseDownloadUrl(
        "https://github.com/gojimq/swft/releases/download/v0.2.0/t3-0.2.0-darwin-arm64.tar.gz",
      ),
    ).toEqual({
      owner: "gojimq",
      repo: "swft",
      tag: "v0.2.0",
      assetName: "t3-0.2.0-darwin-arm64.tar.gz",
    });

    expect(
      parseGitHubReleaseDownloadUrl(
        "https://github.com/gojimq/swft/releases/download/v0.2.0-beta.1/SHA256SUMS?raw=1",
      ),
    ).toEqual({
      owner: "gojimq",
      repo: "swft",
      tag: "v0.2.0-beta.1",
      assetName: "SHA256SUMS",
    });

    expect(
      parseGitHubReleaseDownloadUrl("http://github.com/gojimq/swft/releases/download/v0.2.0/a"),
    ).toBeUndefined();
    expect(
      parseGitHubReleaseDownloadUrl(
        "https://updates.example.com/gojimq/swft/releases/download/v0.2.0/a",
      ),
    ).toBeUndefined();
    expect(
      parseGitHubReleaseDownloadUrl("https://github.com/gojimq/swft/releases/tag/v0.2.0"),
    ).toBeUndefined();
    expect(
      parseGitHubReleaseDownloadUrl("https://github.com/gojimq/swft/releases/download/v0.2.0"),
    ).toBeUndefined();
    expect(
      parseGitHubReleaseDownloadUrl("https://github.com/gojimq/swft/releases/download/v0.2.0/a/b"),
    ).toBeUndefined();
    expect(parseGitHubReleaseDownloadUrl("not a url")).toBeUndefined();
  });
});
