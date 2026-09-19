"""Build a Release Caret.app, optional DMG, and optional /Applications install."""

from pathlib import Path
import shutil
import subprocess
import sys


root = Path(__file__).resolve().parent.parent
bundle = root / ".local/build/Release/Caret.app"
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
    plist = dist_app / "Contents" / "Info.plist"
    if plist.is_file():
        subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", f"Set :CaretProjectRoot {root}", str(plist)],
            check=False,
        )
        subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", f"Add :CaretProjectRoot string {root}", str(plist)],
            check=False,
        )
    print(f"Built {dist_app}")


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
    if not args:
        print("Add --install to copy Caret.app into /Applications, or --dmg to write dist/Caret.dmg.")
