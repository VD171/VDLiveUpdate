#!/usr/bin/env bash
# ======================================================================
#  VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
#  A self-update engine for KernelSU/APatch/Magisk modules.
#
#  Copyright (C) 2026  VD171
#  SPDX-License-Identifier: Apache-2.0
#
#  Site           : https://vd171.ru
#  Site           : https://vd.priv8.ru
#  Source         : https://github.com/VD171/VDLiveUpdate
#  GitHub         : @VD171 https://github.com/VD171
#  XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
#  Telegram       : @VD_Priv8 https://t.me/VD_Priv8
#  Channel        : @Priv8_VD https://t.me/Priv8_VD
#  Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
#  E-mail         : vd.priv8@pm.me
# ======================================================================
# Reproducible build of ed25519-mini (verify-only, dynamic against bionic libc).
# Needs Android NDK r29. Outputs <abi>/ed25519-mini for arm64-v8a, armeabi-v7a, x86, x86_64.
set -euo pipefail
NDK="${NDK:-/home/vd/Android/ndk/android-ndk-r29}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
build() {
  mkdir -p "$2"
  "$TC/$1" -O2 -ffunction-sections -fdata-sections -Wl,--gc-sections \
    -o "$2/ed25519-mini" main.c tweetnacl.c
  "$TC/llvm-strip" "$2/ed25519-mini"
}
build aarch64-linux-android28-clang   arm64-v8a
build armv7a-linux-androideabi28-clang armeabi-v7a
build i686-linux-android28-clang      x86
  build x86_64-linux-android28-clang    x86_64
