# Third-party sources

`sources.json` records exact upstream commits. Each `packages/` entry is a Git submodule, not code relicensed by Caret. Preserve upstream copyright and license notices when extracting code. The root MIT license covers original Caret files only. No upstream code runs in the default starter.

`.summem/summem` is the [SumMem](https://github.com/texarkanine/SumMem) 0.12.0 script (`64ce35c89ba0982c74ba8207c3f3a37a2fbf2f21`), AGPL-3.0 with additional permissions in that file's header. Invoking the script does not make this repository a covered work. The `AGENTS.md` bootstrap prompt is 0BSD. SumMem is agent memory, not a `packages/` pin.

| Upstream | License at pin |
| --- | --- |
| KeyType, GhostType | MIT |
| Computer Use Jev | MIT |
| Skyvern | AGPL-3.0 |
| Screenpipe `892199f…` | MIT for the repository except `ee/`, which retains its separate enterprise license |

Screenpipe's later releases use a commercial license. This starter deliberately pins the earlier commit. Do not copy its `ee/` code or apply newer upstream changes assuming they are MIT. Review the license at the exact revision before changing any pin or distributing integrated code.

Skyvern contains a nested submodule. Its dependencies retain their own licenses and are not initialized by the default setup. Screenpipe also declares Git LFS assets. Keep source trees separate from Caret's shipped executable until the selected integrations are implemented and their dependencies checked.
