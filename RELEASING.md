# Cutting a release

Releases exist so there's a version to point at when someone says "it broke."
Publishing one also posts to Slack through the GitHub app, so the notes are the
announcement — write them for the people who have to run the update.

## Versioning

The repo gets its own tag, `vMAJOR.MINOR.PATCH`. This is separate from the
`# VERSION:` lines inside the two scripts, which keep their own numbers.

| Bump | When |
|---|---|
| patch | a fix, no change to how anything is used |
| minor | new option, new menu entry, new device type |
| major | something people have to re-learn or re-do by hand |

## Steps

1. Make sure `main` is clean and pushed, and the `# VERSION:` lines in both
   scripts reflect what changed.

2. Write the notes. Lead with **how to update**, then what's new — the Slack
   message truncates, so the update command should be near the top.

   ```bash
   cd ~/shivs-cool-log-script
   $EDITOR /tmp/notes.md
   ```

3. Tag and publish:

   ```bash
   git tag -a v1.1.0 -m "v1.1.0"
   git push origin v1.1.0
   gh release create v1.1.0 --title "v1.1.0 — short summary" --notes-file /tmp/notes.md
   ```

   Or let `gh` make the tag for you and skip the two `git` lines.

4. Check the Slack channel actually got it.

## If you need to take one back

```bash
gh release delete v1.1.0 --yes
git push origin :refs/tags/v1.1.0
git tag -d v1.1.0
```

The Slack message stays up — it's already been posted. Publish a follow-up
release saying what happened rather than trying to make it look like it didn't.
