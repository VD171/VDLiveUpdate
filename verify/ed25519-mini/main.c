/*
 * ======================================================================
 *  VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
 *  A self-update engine for KernelSU/APatch/Magisk modules.
 *
 *  Copyright (C) 2026  VD171
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Site           : https://vd171.ru
 *  Site           : https://vd.priv8.ru
 *  Source         : https://github.com/VD171/VDLiveUpdate
 *  GitHub         : @VD171 https://github.com/VD171
 *  XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
 *  Telegram       : @VD_Priv8 https://t.me/VD_Priv8
 *  Channel        : @Priv8_VD https://t.me/Priv8_VD
 *  Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
 *  E-mail         : vd.priv8@pm.me
 * ======================================================================
 */
/* ed25519-mini: standalone ed25519 signature verifier (verify-only).
 *
 *   ed25519-mini <pubkey32> <msg> <sig64>
 *     pubkey32 : raw 32-byte ed25519 public key
 *     msg      : the exact bytes that were signed
 *     sig64    : raw 64-byte ed25519 signature
 *   rc: 0 = valid, 1 = invalid signature, 2 = usage / I/O / parse error.
 *
 * Crypto is TweetNaCl (D. J. Bernstein et al., public domain). Verify is
 * crypto_sign_open over a signed message built as sig||msg (detached verify).
 * No hashing of the message here: the caller passes the exact signed bytes.
 */
#include "tweetnacl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* crypto_sign_open never calls randombytes; this only satisfies the linker and
 * aborts loudly if a future code path ever reaches it. */
void randombytes(unsigned char *x, unsigned long long n) {
    (void)x; (void)n;
    fprintf(stderr, "ed25519-mini: randombytes called in a verify-only build\n");
    _exit(2);
}

static long read_file(const char *path, unsigned char **out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    long n = ftell(f);
    if (n < 0 || fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -1; }
    unsigned char *b = malloc((size_t)(n ? n : 1));
    if (!b) { fclose(f); return -1; }
    if (n && fread(b, 1, (size_t)n, f) != (size_t)n) { free(b); fclose(f); return -1; }
    fclose(f);
    *out = b;
    return n;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <pubkey32> <msg> <sig64>\n", argv[0]);
        return 2;
    }
    unsigned char *pk = NULL, *msg = NULL, *sig = NULL;
    long pkn = read_file(argv[1], &pk);
    long msgn = read_file(argv[2], &msg);
    long sign = read_file(argv[3], &sig);
    int rc = 2;
    if (pkn != 32) { fprintf(stderr, "ed25519-mini: public key must be 32 bytes (got %ld)\n", pkn); goto out; }
    if (sign != 64) { fprintf(stderr, "ed25519-mini: signature must be 64 bytes (got %ld)\n", sign); goto out; }
    if (msgn < 0) { fprintf(stderr, "ed25519-mini: cannot read message\n"); goto out; }

    unsigned long long smlen = 64ULL + (unsigned long long)msgn;
    unsigned char *sm = malloc((size_t)smlen);
    unsigned char *m = malloc((size_t)smlen);
    if (!sm || !m) { fprintf(stderr, "ed25519-mini: out of memory\n"); free(sm); free(m); goto out; }
    memcpy(sm, sig, 64);
    if (msgn) memcpy(sm + 64, msg, (size_t)msgn);

    unsigned long long mlen = 0;
    int r = crypto_sign_open(m, &mlen, sm, smlen, pk);
    free(sm); free(m);
    rc = (r == 0) ? 0 : 1;
out:
    free(pk); free(msg); free(sig);
    return rc;
}
