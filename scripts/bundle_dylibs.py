#!/usr/bin/env python3
"""Copy MacPorts/Homebrew dylibs (and their deps from the same prefix) into <stage>/lib and make
them relocatable.

Wine loads gnutls, freetype and vulkan via dlopen() by bare name, so the
start script has to put <stage>/lib on DYLD_FALLBACK_LIBRARY_PATH. Inside the
bundle every copied library references its siblings via @loader_path.
"""
import os
import shutil
import subprocess
import sys

BREW_PREFIXES = ("/opt/local/", "/usr/local/", "/opt/homebrew/")


def deps(path):
    out = subprocess.run(["otool", "-L", path], check=True,
                         capture_output=True, text=True).stdout
    return [line.split(" (")[0].strip() for line in out.splitlines()[1:]]


def main():
    stage, direct = sys.argv[1], sys.argv[2:]
    libdir = os.path.join(stage, "lib")
    os.makedirs(libdir, exist_ok=True)

    copied = {}  # realpath -> basename in libdir
    queue = list(direct)
    while queue:
        src = queue.pop()
        real = os.path.realpath(src)
        if real in copied:
            continue
        name = os.path.basename(src)
        dst = os.path.join(libdir, name)
        print(f"copy {real} -> {dst}")
        shutil.copy2(real, dst)
        os.chmod(dst, 0o755)
        copied[real] = name
        for d in deps(real):
            if d.startswith(BREW_PREFIXES):
                queue.append(d)

    for real, name in copied.items():
        dst = os.path.join(libdir, name)
        cmd = ["install_name_tool", "-id", f"@rpath/{name}"]
        for d in deps(dst):
            if d.startswith(BREW_PREFIXES):
                target = copied.get(os.path.realpath(d))
                if target:
                    cmd += ["-change", d, f"@loader_path/{target}"]
        subprocess.run(cmd + [dst], check=True)
        # install_name_tool invalidates the signature; re-sign ad hoc
        subprocess.run(["codesign", "--force", "--sign", "-", dst], check=True)

    for real, name in sorted(copied.items(), key=lambda kv: kv[1]):
        print(name)
        for d in deps(os.path.join(libdir, name)):
            if d.startswith(BREW_PREFIXES):
                sys.exit(f"unresolved package-manager reference in {name}: {d}")


if __name__ == "__main__":
    main()
