#!/usr/bin/env python3
# Hash table capacities: 7 (an empty table's), then for each target 11 * 2^(i/4) up to above 2^31, the smallest prime >= target such that
#  - it is not within 5% of a power of two;
#  - above 288 it divides no 256^k + a, 1 <= k <= 8, |a| <= 32 (Knuth; Pharo's HashTableSizes);
#  - above SPECTRAL_FROM, for every 1 <= k <= 8 with 256^(2k) >= p, no nonzero (c, a) with c * 256^k = a (mod p)
#    is shorter than ALPHA * sqrt(p) (a 2-D spectral test: keys c * 256^k + a, e.g. x * 65536 + y, stay apart).
import math, sys

ALPHA = 0.5
SPECTRAL_FROM = 1024

def is_prime(n):
    if n < 2: return False
    for q in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % q == 0: return n == q
    d, s = n - 1, 0
    while d % 2 == 0: d, s = d // 2, s + 1
    for a in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        x = pow(a, d, n)
        if x in (1, n - 1): continue
        for _ in range(s - 1):
            x = x * x % n
            if x == n - 1: break
        else: return False
    return True

def near_power_of_two(p, tol):
    m = 1
    while m < 4 * p:
        if abs(p - m) <= tol * m: return True
        m *= 2
    return False

def divides_radix_form(p, kmax=8, amax=32):
    for k in range(1, kmax + 1):
        r = pow(256, k, p)
        if r <= amax or r >= p - amax: return True
    return False

def shortest2(r, p):
    """Squared length of the shortest nonzero (c, a) with c * r = a (mod p) (Gauss reduction)."""
    u, v = (1, r % p), (0, p)
    def n2(w): return w[0] * w[0] + w[1] * w[1]
    while True:
        if n2(v) < n2(u): u, v = v, u
        m = (u[0] * v[0] + u[1] * v[1] + n2(u) // 2) // n2(u)
        if m == 0: return n2(u)
        v = (v[0] - m * u[0], v[1] - m * u[1])

def spectral_ok(p, alpha=ALPHA):
    return all(shortest2(pow(256, k, p), p) >= alpha * alpha * p for k in range(1, 9) if 256 ** (2 * k) >= p)

def good(p, tol):
    return (is_prime(p) and not near_power_of_two(p, tol)
            and (p <= 288 or not divides_radix_form(p))
            and (p < SPECTRAL_FROM or spectral_ok(p)))

def capacities(tol=0.05, start=11, per_octave=4, limit=2**31, smallest=7):
    out = [smallest]
    i = 0
    while True:
        target = math.ceil(start * 2 ** (i / per_octave))
        p = max(target, out[-1] + 1)
        while not good(p, tol):
            m = 1 << (p.bit_length() - 1)
            p = max(p + 1, int(m * (1 + tol)) + 1) if p < m * (1 + tol) else p + 1
            if p >= 2 * m * (1 - tol): p = int(2 * m * (1 + tol)) + 1
        out.append(p)
        if p > limit: return out
        i += 1

if __name__ == '__main__':
    cs = capacities()
    print(len(cs), 'max step', max(b / a for a, b in zip(cs, cs[1:])), file=sys.stderr)
    print(' '.join(map(str, cs)))
