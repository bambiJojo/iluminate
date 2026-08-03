//  ReaderVisuals.metal
//  Ilumionate
//
//  Reader background effects. Every function shares one uniform list —
//  (bounds, time, tint, speed, amplitude) — so a mismatch between Swift and
//  Metal is impossible by inspection.
//
//  `bounds` comes from SwiftUI's `Shader.Argument.boundingRect`, NOT from a
//  GeometryReader. The Task 1 spike showed a GeometryReader-supplied size
//  fails inside the reader's macOS window-filling cover, leaving the shader
//  with no usable extent. boundingRect is filled by SwiftUI itself and does
//  not depend on the surrounding layout resolving a proxy.
//
//  `speed` is the normalised value from ReaderVisualModulator, capped at 0.45.
//
//  SAFETY: no effect may make a repeating feature cross a fixed pixel at 3 Hz
//  or more. Each effect states its own arithmetic at the maximum speed.

#include <metal_stdlib>
using namespace metal;

static constant float kTau = 6.2831853;

/// Erases the effect where the word sits. The word is pivot-anchored at the
/// view's centre and is far wider than it is tall, so the protected region is
/// a squashed ellipse. Every effect multiplies its alpha by this, which is why
/// there is no scrim overlay anywhere in the reader.
static half centreFade(float2 pos, float2 size) {
    float2 d = (pos - size * 0.5) / max(size * 0.5, float2(1.0));
    d.y /= 0.46;                     // wide-and-short protected region
    return half(smoothstep(0.35, 1.0, length(d)));
}

/// Normalised radius, 0 at centre and 1 at the nearer edge.
static float unitRadius(float2 pos, float2 size) {
    return length(pos - size * 0.5) / max(min(size.x, size.y) * 0.5, 1.0);
}

/// Fades every effect out near the frame edges so nothing terminates abruptly.
static half edgeFade(float r) {
    return half(1.0 - smoothstep(0.85, 1.35, r));
}

/// SwiftUI expects premultiplied colour out of a colorEffect shader.
static half4 composite(half4 tint, half alpha) {
    return half4(tint.rgb * alpha, alpha);
}

// MARK: - Spiral
// 5 arms x speed 0.45 = 2.25 Hz per pixel. Under 3 Hz.
[[ stitchable ]] half4 readerSpiral(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude) {
    float2 size = bounds.zw;
    float2 c = pos - size * 0.5;
    float r = unitRadius(pos, size);
    float a = atan2(c.y, c.x);
    // The r term is what turns rays into a spiral.
    float v = sin(a * 5.0 + r * 9.0 - time * speed * kTau);
    half arms = half(smoothstep(0.0, 0.6, v));
    half alpha = arms * edgeFade(r) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Tunnel
// 6 rings x speed 0.45 = 2.7 Hz per pixel. Under 3 Hz.
[[ stitchable ]] half4 readerTunnel(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude) {
    float2 size = bounds.zw;
    float r = unitRadius(pos, size);
    // pow compresses rings toward the centre, which reads as depth. 0.45 rather
    // than 0.65: at the shallower exponent the rings were near-evenly spaced and
    // read as concentric ripples, not a tunnel. Ring COUNT stays at 6 — 7 would
    // put the per-pixel rate at 7 x 0.45 = 3.15 Hz, over the ceiling.
    float depth = pow(max(r, 0.02), 0.45);
    float v = sin(kTau * (depth * 6.0 - time * speed * 6.0));
    half rings = half(smoothstep(0.1, 0.75, v));
    half alpha = rings * edgeFade(r) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Moire
// Motion here is the OFFSET drifting, not rings sweeping past. Ring density is
// ~14 across the half-width, so a sweeping term would breach 3 Hz (14 x 0.45 =
// 6.3 Hz); the drifting offset changes any pixel's local phase far more slowly.
[[ stitchable ]] half4 readerMoire(float2 pos, half4 color, float4 bounds,
                                   float time, half4 tint,
                                   float speed, float amplitude) {
    float2 size = bounds.zw;
    float2 centre = size * 0.5;
    float2 offset = float2(sin(time * speed * 0.9), cos(time * speed * 0.7))
                    * size.x * 0.06;
    float k = kTau / max(size.x / 14.0, 1.0);
    float v = sin(length(pos - centre - offset) * k)
            * sin(length(pos - centre + offset) * k);
    half interference = half(smoothstep(0.15, 0.85, v));
    half alpha = interference * edgeFade(unitRadius(pos, size))
               * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}

// MARK: - Drift
// Positional motion only — no repeating full-frame luminance cycle, so the
// 3 Hz ceiling does not bind here.
static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

[[ stitchable ]] half4 readerDrift(float2 pos, half4 color, float4 bounds,
                                   float time, half4 tint,
                                   float speed, float amplitude) {
    float2 size = bounds.zw;
    float2 c = (pos - size * 0.5) / max(min(size.x, size.y) * 0.5, 1.0);
    half acc = 0.0h;
    // 40 motes, not 18: at 18 the field read as a handful of stray dots rather
    // than a drifting swarm. Radius spreads past 1.0 on purpose so some motes
    // sit off-frame and sweep through, which is what sells the depth.
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        float aSeed = hash11(fi + 1.0);
        float rSeed = hash11(fi + 37.0);
        float sSeed = hash11(fi + 71.0);
        float bSeed = hash11(fi + 113.0);

        // Independent hashes per parameter — reusing one seed for angle and
        // rate made the motes visibly co-rotate in clumps.
        float rate = 0.35 + 0.85 * sSeed;
        float angle = aSeed * kTau + time * speed * rate;
        // Slow radial breath so the swarm expands and contracts rather than
        // riding fixed rings.
        float breath = 1.0 + 0.18 * sin(time * speed * 0.42 + bSeed * kTau);
        float radius = (0.12 + 1.13 * rSeed) * breath;

        // `c` is normalised by half-WIDTH, so on a tall phone c.y reaches ~2.1.
        // A fixed 0.82 vertical scale therefore penned the swarm into the middle
        // half of the screen; scaling by aspect lets it fill the frame.
        float aspect = size.y / max(size.x, 1.0);
        float2 p = float2(cos(angle) * radius, sin(angle) * radius * aspect * 0.92);
        float d = length(c - p);
        // Softer, larger motes with size variance; the old 320 falloff made
        // them pinpricks that vanished against the background.
        float spread = 70.0 + 130.0 * sSeed;
        acc += half(exp(-d * d * spread) * (0.55 + 0.45 * bSeed));
    }
    half alpha = min(acc, 1.0h) * half(amplitude) * centreFade(pos, size);
    return composite(tint, alpha);
}
