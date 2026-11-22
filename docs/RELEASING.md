# Releasing Dialup

Releases are built by GitHub Actions ([`.github/workflows/release.yml`](../.github/workflows/release.yml)) when a version tag is pushed.

## Making a release

1. Set `MARKETING_VERSION` in `project.yml` (for example `0.2.0`) and move the CHANGELOG's "not released yet" heading to the version and date.
2. Commit and push to `main`.
3. Tag and push: `git tag -a v0.2.0 -m "Dialup 0.2.0" && git push origin v0.2.0`.

The workflow then:

- builds a universal (Apple silicon + Intel), ad-hoc signed Release app. The build number (`CFBundleVersion`) is the commit count, so it always goes up; Sparkle compares it to decide what's newer;
- stops if the tag doesn't match the app's version;
- zips it to `Dialup.zip` and writes `Dialup.zip.sha256` (`install.sh` checks it);
- signs the zip with the update key and writes `appcast.xml` (Sparkle's `generate_appcast`);
- publishes the GitHub release with all three files, using `.github/release-notes.md` as the text.

The [website workflow](../.github/workflows/pages.yml) publishes `site/` to GitHub Pages with every published release (or by hand from the Actions tab).

## How updates find a release

Dialup reads `https://github.com/viktorfroberg/Dialup/releases/latest/download/appcast.xml` (`SUFeedURL`, set from `DIALUP_FEED_URL` in `project.yml`). "Latest" is the newest release that isn't a draft or pre-release, so:

- **every release must carry `appcast.xml`**; don't delete it from the newest release;
- **pre-releases are a safe test channel**: they never reach users. To test an update, build two versions with a higher build number pointed at the pre-release's feed (`DIALUP_FEED_URL=https://github.com/viktorfroberg/Dialup/releases/download/<tag>/appcast.xml`).

## The update signing key

Sparkle only installs an update whose EdDSA signature matches `SUPublicEDKey` in `project.yml`.

- The private key lives in the maintainer's login keychain (account `dialup`) and in the `SPARKLE_PRIVATE_KEY` Actions secret. Keep an offline backup (a password manager): **if the key is lost, installed copies can't update automatically any more**; Sparkle can rotate keys, but only with the old key.
- To put the key in the secret (from Sparkle's tools, [download](https://github.com/sparkle-project/Sparkle/releases)):

  ```sh
  ./bin/generate_keys --account dialup -x key.tmp && gh secret set SPARKLE_PRIVATE_KEY < key.tmp && rm -P key.tmp
  ```

## Gatekeeper

Dialup is ad-hoc signed, not notarized (that needs a paid Apple Developer ID). A zip downloaded in a browser is quarantined, so the first launch needs System Settings → Privacy & Security → Open Anyway. `install.sh` downloads with curl, which doesn't quarantine, so it opens without the warning. Updates installed by Sparkle aren't quarantined either.
