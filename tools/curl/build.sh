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
# Reproducible static-TLS curl for VDLU tools-feed. Needs Android NDK r29 + cmake.
# Per ABI: mbedTLS 3.6.7 static + curl 8.11.1 (HTTP_ONLY, mbedTLS backend), linked
# statically for TLS but DYNAMIC against bionic libc/libm/libdl (no .so closure).
set -euo pipefail
NDK="${NDK:-/home/vd/Android/ndk/android-ndk-r29}"
TC="$NDK/build/cmake/android.toolchain.cmake"
STRIP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
: "${MBEDTLS_SRC:?path to extracted mbedtls-3.6.7}"; : "${CURL_SRC:?path to extracted curl-8.11.1}"
for ABI in arm64-v8a armeabi-v7a x86 x86_64; do
  P="$PWD/mbedtls-$ABI"
  cmake -S "$MBEDTLS_SRC" -B "mb-$ABI" -DCMAKE_TOOLCHAIN_FILE="$TC" -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-28 \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
  cmake --build "mb-$ABI" -j4; cmake --install "mb-$ABI" --prefix "$P"
  cmake -S "$CURL_SRC" -B "cu-$ABI" -DCMAKE_TOOLCHAIN_FILE="$TC" -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-28 \
    -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF -DBUILD_CURL_EXE=ON -DBUILD_LIBCURL_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DBUILD_TESTING=OFF \
    -DCURL_USE_MBEDTLS=ON -DMBEDTLS_INCLUDE_DIR="$P/include" -DMBEDTLS_LIBRARY="$P/lib/libmbedtls.a" -DMBEDX509_LIBRARY="$P/lib/libmbedx509.a" -DMBEDCRYPTO_LIBRARY="$P/lib/libmbedcrypto.a" \
    -DHTTP_ONLY=ON -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_NGHTTP2=OFF -DUSE_NGHTTP3=OFF -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_LIBIDN2=OFF -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON
  cmake --build "cu-$ABI" -j4; mkdir -p "$ABI"; cp "$(find cu-$ABI -name curl -type f | head -1)" "$ABI/curl"; "$STRIP" "$ABI/curl"
done
