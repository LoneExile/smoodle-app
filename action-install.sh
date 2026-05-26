#!/usr/bin/env bash

set -e

rime_version=1.16.1
rime_git_hash="de4700e"
sparkle_version=2.6.2

rime_archive="rime-${rime_git_hash}-macOS-universal.tar.bz2"
rime_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_archive}"

rime_deps_archive="rime-deps-${rime_git_hash}-macOS-universal.tar.bz2"
rime_deps_download_url="https://github.com/rime/librime/releases/download/${rime_version}/${rime_deps_archive}"

sparkle_archive="Sparkle-${sparkle_version}.tar.xz"
sparkle_download_url="https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/${sparkle_archive}"

mkdir -p download && (
    cd download
    [ -z "${no_download}" ] && curl -LO "${rime_download_url}"
    tar --bzip2 -xf "${rime_archive}"
    [ -z "${no_download}" ] && curl -LO "${rime_deps_download_url}"
    tar --bzip2 -xf "${rime_deps_archive}"
    [ -z "${no_download}" ] && curl -LO "${sparkle_download_url}"
    tar -xJf "${sparkle_archive}"
)

mkdir -p librime/share
mkdir -p Frameworks
cp -R download/dist librime/
cp -R download/share/opencc librime/share/
cp -R download/Sparkle.framework Frameworks/

# skip building librime and opencc-data; use downloaded artifacts.
# This copies the UPSTREAM librime + tools (rime_deployer, rime_dict_manager)
# from librime/dist into lib/ + bin/.
make copy-rime-binaries copy-opencc-data

# v0.0.8a: overwrite the upstream librime.dylib with the smoodle-patched
# build (peek-sort fix, smoodle-type/librime@1.16.0-smoodle.1). Without
# this, the bundled dylib is plain upstream librime and the patch never
# ships. Force re-fetch via Makefile's download-librime target.
rm -f lib/librime.1.dylib
make download-librime

SQUIRREL_BUNDLED_RECIPES="${SQUIRREL_BUNDLED_RECIPES:-prelude essay}"
echo "SQUIRREL_BUNDLED_RECIPES=${SQUIRREL_BUNDLED_RECIPES}"

git submodule update --init plum
# install Rime recipes (scoped to prelude+essay by default — the
# minimum for smoodle. Override via env if other schemas needed.)
rime_dir=plum/output bash plum/rime-install ${SQUIRREL_BUNDLED_RECIPES}
make copy-plum-data
