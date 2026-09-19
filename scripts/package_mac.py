"""Build a Release Caret.app, optional DMG, and optional /Applications install."""

from pathlib import Path
import shutil
import subprocess
import sys


root = Path(__file__).resolve().parent.parent
derived_data = root / ".local" / "DerivedData"
bundle = derived_data / "Build" / "Products" / "Release" / "Caret.app"
dist_app = root / "dist/Caret.app"
dmg = root / "dist/Caret.dmg"


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def build() -> None:
    run([
        "xcodebuild",
        "-project", str(root / "Caret.xcodeproj"),
        "-scheme", "Caret",
        "-configuration", "Release",
        "-destination", "platform=macOS",
        "-derivedDataPath", str(derived_data),
        "CODE_SIGN_IDENTITY=-",
        "build",
    ])
    if not bundle.exists():
        raise SystemExit(f"Missing Release app at {bundle}")
    dist_app.parent.mkdir(parents=True, exist_ok=True)
    if dist_app.exists():
        shutil.rmtree(dist_app)
    shutil.copytree(bundle, dist_app, symlinks=True)
    seed_src = root / "caret" / "notes"
    seed_dst = dist_app / "Contents" / "Resources" / "NotesSeed"
    if seed_src.is_dir():
        if seed_dst.exists():
            shutil.rmtree(seed_dst)
        shutil.copytree(seed_src, seed_dst)
    stamp_project_root(dist_app, root=root, release=_release_mode())
    adhoc_sign(dist_app)
    print(f"Built {dist_app}")


def _release_mode() -> bool:
    return "--release" in set(sys.argv[1:]) or __import__("os").environ.get("CARET_RELEASE_DMG") == "1"


def stamp_project_root(dist_app: Path, *, root: Path, release: bool) -> None:
    plist = dist_app / "Contents" / "Info.plist"
    if not plist.is_file():
        return
    if release:
        # Distributed builds must not embed a CI machine path. Users set
        # CARET_PROJECT_ROOT or ~/.config/caret/dev.json "root" for the Python core.
        subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", "Delete :CaretProjectRoot", str(plist)],
            check=False,
        )
        return
    subprocess.run(
        ["/usr/libexec/PlistBuddy", "-c", f"Set :CaretProjectRoot {root}", str(plist)],
        check=False,
    )
    subprocess.run(
        ["/usr/libexec/PlistBuddy", "-c", f"Add :CaretProjectRoot string {root}", str(plist)],
        check=False,
    )


def adhoc_sign(dist_app: Path) -> None:
    """Re-seal after post-build edits (Info.plist, NotesSeed). Without this,
    Gatekeeper reports the app as damaged on download."""
    run([
        "codesign",
        "--force",
        "--deep",
        "--sign", "-",
        str(dist_app),
    ])
    verify = subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(dist_app)],
        capture_output=True,
        text=True,
    )
    if verify.returncode != 0:
        raise SystemExit(
            f"codesign verify failed for {dist_app}:\n{verify.stderr or verify.stdout}"
        )


def make_dmg() -> None:
    if dmg.exists():
        dmg.unlink()
    staging = root / ".local/dmg"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    shutil.copytree(dist_app, staging / "Caret.app", symlinks=True)
    (staging / "Applications").symlink_to("/Applications")
    run([
        "hdiutil", "create",
        "-volname", "Caret",
        "-srcfolder", str(staging),
        "-ov", "-format", "UDZO",
        str(dmg),
    ])
    print(f"Created {dmg}")


def install() -> None:
    destination = Path("/Applications/Caret.app")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(dist_app, destination, symlinks=True)
    print(f"Installed {destination}")
    print(
        "If Caret already looks enabled in Accessibility, remove Caret (−), "
        "click +, choose /Applications/Caret.app, then turn it on again."
    )
    run(["open", str(destination)])


if __name__ == "__main__":
    args = set(sys.argv[1:])
    build()
    if "--dmg" in args:
        make_dmg()
    if "--install" in args:
        install()
    if not args or args <= {"--release"}:
        print(
            "Add --install to copy Caret.app into /Applications, "
            "--dmg to write dist/Caret.dmg, and --release for GitHub distribution "
            "(omits CaretProjectRoot in the bundle)."
        )
