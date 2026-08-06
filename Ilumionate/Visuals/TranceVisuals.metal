//  TranceVisuals.metal
//  Ilumionate
//
//  Background effects for both surfaces that draw a field: the reader, behind
//  its words, and the Create tab's wordless Visual Field, as the whole screen.
//
//  Every function shares one uniform list —
//  (bounds, time, tint, speed, amplitude, rate, focus) — so a mismatch between
//  Swift and Metal is impossible by inspection. Keep this list in step with
//  VisualFieldLayer's argument order; nothing else checks it, because
//  ShaderLibrary resolves at runtime and a mismatch is a blank frame rather
//  than a build error.
//
//  `bounds` comes from SwiftUI's `Shader.Argument.boundingRect`, NOT from a
//  GeometryReader. The Task 1 spike showed a GeometryReader-supplied size
//  fails inside the reader's macOS window-filling cover, leaving the shader
//  with no usable extent. boundingRect is filled by SwiftUI itself and does
//  not depend on the surrounding layout resolving a proxy.
//
//  `speed` is the normalised value from VisualModulation.speedBand, capped at
//  0.45. `rate` is the effect's own feature-crossing rate, supplied by Swift
//  from TranceVisual.motionRate rather than hardcoded here, so the
//  photosensitivity budget is enforced by a test instead of by comments. Its
//  SIGN carries VisualDirection; its magnitude is what the budget measures.
//  `focus` is how much of the centre focus well to apply — 1 for the reader,
//  which has a word to protect, 0 for the wordless field, which does not.
//
//  DESIGN: effects converge INWARD by default, toward the word at the centre.
//  The reader's focus should be pulled to the word, never pushed to the frame
//  edge, so the reader never passes a negative rate. See
//  docs/superpowers/specs/2026-08-04-reader-focus-visuals-design.md and
//  docs/superpowers/specs/2026-08-05-create-tab-visual-field-design.md.
//
//  SAFETY: no effect may make a repeating feature cross a fixed pixel at 3 Hz
//  or more. Because every effect uses the phase rule below, that rate is
//  `speed * rate` everywhere in the frame — see VisualModulation.swift.

#include <metal_stdlib>
using namespace metal;

static constant float kTau = 6.2831853;
static constant float kPi  = 3.14159265;

// MARK: - Shared grammar
//
// The one rule every effect obeys:
//
//     phase = convergentDepth(r, turns) * density - time * speed * rate
//
// `convergentDepth` FALLS with r, so subtracting time makes constant-phase
// surfaces travel toward r = 0. Adding time instead reverses the direction of
// travel and pushes the eye out of the frame — that was the bug in the previous
// tunnel, and it is the single easiest thing to get wrong in this file.

/// Perspective depth: `turns` at the centre, falling to ~1 at the frame edge.
/// Feature density scales as turns² toward the centre, so the middle reads as
/// bottomless.
///
/// The `1.0 / turns` guard is load-bearing. Without it the gradient diverges at
/// r = 0; with it the peak gradient is exactly `density * turns²`, which is what
/// makes the antialiasing width below computable rather than unbounded.
static float convergentDepth(float r, float turns) {
    return 1.0 / (r + 1.0 / turns);
}

/// How much `phase` changes across one point — the same quantity `fwidth()`
/// would return, derived in closed form instead.
///
/// `fwidth` would be more general, but SwiftUI stitchable functions are inlined
/// into a fragment shader by machinery we do not control, and derivatives are
/// undefined under the non-uniform control flow readerDrift's loop contains.
/// The closed form has neither caveat and costs one divide.
static float depthGradient(float r, float turns, float density, float halfMin) {
    float g = r + 1.0 / turns;
    return density / max(g * g * halfMin, 1e-4);
}

static float triwave(float v) {
    return 1.0 - abs(2.0 * v - 1.0);
}

/// A band centred on each integer step of `y`, antialiased by its own gradient.
///
/// `thickness` is the half-width of the band in phase units: small values give
/// hairlines, 0.5 gives a 50% duty cycle. As the rings compress toward the
/// centre `dydp` grows past `thickness`, the smoothstep widens past the whole
/// range of `d`, and the band resolves to flat tone rather than to moiré.
///
/// That dissolve is not cosmetic. On a 1x display the proposed parameters
/// breach Nyquist at the vanishing point, and an aliased pattern beating against
/// the pixel grid as it moves produces flicker the `speed * rate` budget does
/// not account for.
static half ringBand(float y, float dydp, float thickness) {
    float d = abs(fract(y) - 0.5) * 2.0;   // 0 on the ridge, 1 between ridges
    float w = max(dydp, 0.001);
    return half(1.0 - smoothstep(thickness - w, thickness + w, d));
}

/// Normalised radius, 0 at centre and 1 at the nearer edge.
static float unitRadius(float2 pos, float2 size) {
    return length(pos - size * 0.5) / max(min(size.x, size.y) * 0.5, 1.0);
}

static float halfMinDimension(float2 size) {
    return max(min(size.x, size.y) * 0.5, 1.0);
}

/// Normalised radius against the FARTHER edge — 1 at the middle of the long
/// side rather than the short one.
///
/// `unitRadius` divides by the nearer edge, so on a tall phone `edgeFade` was
/// fully dark 1.28 half-widths out: on a 402x874 frame that is 257pt from
/// centre against a 437pt half-height, leaving the top and bottom fifths of the
/// screen permanently black. Fading on this radius instead lets the field reach
/// the short edges and only vignettes the corners.
///
/// Deliberately separate from `unitRadius`: feature scale still keys off the
/// short side, so ring spacing — and with it the `featureCount * speed`
/// flicker budget — is unchanged. This affects alpha only.
static float coverageRadius(float2 pos, float2 size) {
    return length(pos - size * 0.5) / max(max(size.x, size.y) * 0.5, 1.0);
}

/// Erases the effect where the word sits, leaving a still, dark well the
/// converging field falls into. The word is pivot-anchored at the view's centre
/// and far wider than tall, so the protected region is a squashed ellipse.
/// Every effect multiplies its alpha by this, which is why there is no scrim
/// overlay anywhere in the reader.
///
/// The band is tighter than the old 0.35…1.0: a slow gradient reads as haze,
/// whereas a short transition reads as a rim framing the word.
static half focusWell(float2 pos, float2 size) {
    float2 d = (pos - size * 0.5) / max(size * 0.5, float2(1.0));
    d.y /= 0.46;                     // wide-and-short protected region
    return half(smoothstep(0.26, 0.62, length(d)));
}

/// How much of the focus well to apply. `focus` is 1 for the reader, which needs
/// the well to protect its word, and 0 for the wordless Visual Field, which has
/// no word to protect and wants the compressed centre the well would erase.
///
/// A blend rather than a branch: `focus` is uniform across the frame, so there
/// is no divergence cost, and intermediate values stay available without adding
/// a second code path to reason about.
///
/// Safe to switch off. `ringBand` already dissolves to flat tone where features
/// compress past the pixel grid, so an un-welled centre does not alias against
/// it — see the Nyquist note on ringBand above.
static half focusMask(float2 pos, float2 size, float focus) {
    return mix(1.0h, focusWell(pos, size), half(clamp(focus, 0.0, 1.0)));
}

/// Dims the periphery. Together with focusWell this puts peak brightness in an
/// annulus at r ~ 0.7 — a ring of light around the word, with darkness at both
/// the centre and the corners.
static half edgeFade(float r) {
    return half(1.0 - smoothstep(0.78, 1.28, r));
}

/// SwiftUI expects premultiplied colour out of a colorEffect shader.
static half4 composite(half4 tint, half alpha) {
    return half4(tint.rgb * alpha, alpha);
}

// MARK: - Spiral
// Arms crawl inward. rate 4.0 x speed 0.45 = 1.80 Hz. Under 3 Hz.
[[ stitchable ]] half4 readerSpiral(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude, float rate,
                                    float focus) {
    float2 size = bounds.zw;
    float2 c = pos - size * 0.5;
    float r = unitRadius(pos, size);
    float halfMin = halfMinDimension(size);

    const float turns = 4.0, density = 3.5, arms = 3.0, morphRate = 0.08;

    float a = atan2(c.y, c.x) + kPi;              // 0 … tau
    float ap = fract(a / kTau * arms);            // position within an arm

    float ring = convergentDepth(r, turns) * density - time * speed * rate;
    float arm  = ring + ap;
    float dydp = depthGradient(r, turns, density, halfMin);

    // Ring<->arm morph, adapted from HypnoSwirl's timeMorph so the pattern
    // breathes rather than looping one fixed figure. ~28 s at full speed.
    //
    // The two patterns are CROSSFADED rather than the shear being scaled.
    // Scaling it (`ap * armWeight`) looks equivalent and is not: `ap` steps down
    // by exactly 1 at each arm boundary, which fract() absorbs invisibly, but a
    // step of `armWeight` does not divide evenly and leaves a radial seam at
    // every arm edge. Both patterns here are individually seam-free, so any
    // blend of them is too.
    half morph = half(triwave(fract(time * speed * morphRate)));
    half pattern = mix(ringBand(ring, dydp, 0.26),
                       ringBand(arm,  dydp, 0.26), morph);

    half alpha = pattern * edgeFade(coverageRadius(pos, size)) * half(amplitude) * focusMask(pos, size, focus);
    return composite(tint, alpha);
}

// MARK: - Tunnel
// Rings fall inward and compress at the vanishing point.
// rate 4.0 x speed 0.45 = 1.80 Hz. Under 3 Hz.
[[ stitchable ]] half4 readerTunnel(float2 pos, half4 color, float4 bounds,
                                    float time, half4 tint,
                                    float speed, float amplitude, float rate,
                                    float focus) {
    float2 size = bounds.zw;
    float r = unitRadius(pos, size);
    float halfMin = halfMinDimension(size);

    const float turns = 5.0, density = 4.0;

    float y = convergentDepth(r, turns) * density - time * speed * rate;
    float dydp = depthGradient(r, turns, density, halfMin);

    half alpha = ringBand(y, dydp, 0.24) * edgeFade(coverageRadius(pos, size)) * half(amplitude)
               * focusMask(pos, size, focus);
    return composite(tint, alpha);
}

// MARK: - Moire
// Two ring families on one perspective curve, differing only in count, so the
// beat between them also travels inward. Varying `density` rather than `turns`
// keeps both families on the same depth curve, which is what makes the
// interference read as one surface instead of two.
//
// The product of two bands contains their sum frequency, so the budget counts
// double: rate 3.0 x 2 x speed 0.45 = 2.70 Hz. Under 3 Hz, with the least
// headroom of any effect here — do not raise this rate.
[[ stitchable ]] half4 readerMoire(float2 pos, half4 color, float4 bounds,
                                   float time, half4 tint,
                                   float speed, float amplitude, float rate,
                                   float focus) {
    float2 size = bounds.zw;
    float r = unitRadius(pos, size);
    float halfMin = halfMinDimension(size);

    const float turns = 5.0, densityA = 4.0, densityB = 6.6;

    float depth = convergentDepth(r, turns);
    float travel = time * speed * rate;

    half bandA = ringBand(depth * densityA - travel,
                          depthGradient(r, turns, densityA, halfMin), 0.46);
    half bandB = ringBand(depth * densityB - travel,
                          depthGradient(r, turns, densityB, halfMin), 0.46);

    half alpha = bandA * bandB * edgeFade(coverageRadius(pos, size)) * half(amplitude)
               * focusMask(pos, size, focus);
    return composite(tint, alpha);
}

// MARK: - Drift
// Motes are born at the rim and stream into the well. Positional motion only —
// no repeating full-frame luminance cycle, so the 3 Hz ceiling does not bind.
// `rate` here is lifetime turnover: 0.5 x 0.45 = 0.23 lifetimes/sec.
static float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

[[ stitchable ]] half4 readerDrift(float2 pos, half4 color, float4 bounds,
                                   float time, half4 tint,
                                   float speed, float amplitude, float rate,
                                   float focus) {
    float2 size = bounds.zw;
    float2 c = (pos - size * 0.5) / halfMinDimension(size);

    const float turns = 5.0, winding = 0.8;
    // `c` is normalised by half the SHORTER side, so on a tall phone c.y reaches
    // well past 1. Scaling the mote field by aspect lets it fill the frame
    // instead of being penned into the middle band.
    float aspect = size.y / max(size.x, 1.0);

    half acc = 0.0h;
    for (int i = 0; i < 40; i++) {
        float fi = float(i);
        // Golden-ratio and sqrt(2) spacing for birth and angle, NOT hashes.
        // A hash over 40 motes leaves gaps 243x its own smallest, which packed
        // the swarm into one arc. Both constants are badly-approximable, so the
        // spacing stays near-even, and being different irrationals keeps the
        // birth phase and the angle decorrelated. Size and brightness still
        // hash — clumping there is invisible.
        float birth = fract(fi * 0.6180339887);
        float aSeed = fract(fi * 0.4142135624);
        float sSeed = hash11(fi + 71.0);
        float bSeed = hash11(fi + 113.0);

        // 0 = just born at the rim, 1 = arrived at the well.
        float u = fract(birth + time * speed * rate);

        // Radius follows the INVERSE of convergentDepth, so motes decelerate as
        // they approach the centre. That deceleration is the perspective cue —
        // a linear inbound ramp reads as sliding, not as falling away.
        float d = mix(1.0, turns, u);
        float radius = ((1.0 / d) - (1.0 / turns)) / (1.0 - 1.0 / turns) * 1.3;
        float angle = aSeed * kTau + u * winding * kTau;

        float2 p = float2(cos(angle) * radius,
                          sin(angle) * radius * aspect * 0.92);
        float dist = length(c - p);

        // Motes shrink as they converge: inward is farther away.
        float spread = mix(70.0, 260.0, u) + 60.0 * sSeed;
        // Fade in and out at the ends of a life so nothing pops.
        float life = smoothstep(0.0, 0.07, u) * (1.0 - smoothstep(0.93, 1.0, u));

        acc += half(exp(-dist * dist * spread) * life * (0.55 + 0.45 * bSeed));
    }

    half alpha = min(acc, 1.0h) * half(amplitude) * focusMask(pos, size, focus);
    return composite(tint, alpha);
}

// MARK: - Glass
// A lattice drawn in SPIRAL space: rings that travel inward, crossed with
// spokes that wind with depth, so the whole grid curves into the centre. Each
// colour channel is offset slightly along the depth axis, which is what gives
// the lines their chromatic fringe. Tinted rather than rainbow, so the split
// stays inside the current phase colour.
//
// Two things here were arrived at by rejecting the obvious version.
//
// 1. A warped CARTESIAN grid — 154's construction — stays visually flat however
//    hard it is squeezed, and does not pull the eye anywhere. Drawing the grid
//    in spiral space is what makes it converge.
//
// 2. Animating the squeeze so the lattice itself falls inward cannot fit the
//    flicker budget: it sweeps every grid line radially past every pixel at
//    `p * gridDensity * adjust * spiral * pi * speed * rate`, which is 166 Hz at
//    the frame corner for 154's own parameters and needs
//    `gridDensity * spiral < 0.217` to stay under 3 Hz — some thirty times below
//    anything visible. 154 gets away with it because its motion is a rotation of
//    the whole field and it carries no photosensitivity budget.
//
// So the SPOKES ARE STATIC and only the rings travel. That keeps this at one
// moving feature per unit phase, exactly like Tunnel:
// rate 3.5 x speed 0.45 = 1.58 Hz. Under 3 Hz.

[[ stitchable ]] half4 readerGlass(float2 pos, half4 color, float4 bounds,
                                   float time, half4 tint,
                                   float speed, float amplitude, float rate,
                                   float focus) {
    float2 size = bounds.zw;
    float halfMin = halfMinDimension(size);
    float2 p = (pos - size * 0.5) / halfMin;
    float r = unitRadius(pos, size);

    const float turns = 4.0, density = 3.0, spokes = 10.0;
    const float shear = 1.0, spokeWidth = 0.18, ringWidth = 0.20;

    float a = atan2(p.y, p.x);
    float depth = convergentDepth(r, turns) * density;
    float dydp = depthGradient(r, turns, density, halfMin);
    // Angular gradient in phase-per-point, plus what the winding shear adds.
    // Guarding r keeps this finite at the exact centre.
    float spokeGrad = spokes / (kTau * max(r, 0.02) * halfMin) + shear * dydp;

    float travel = time * speed * rate;

    // Offsetting the whole lattice per channel — rather than only one family —
    // keeps the fringe coherent across rings and spokes alike.
    half3 ch;
    for (int i = 0; i < 3; i++) {
        float offset = (float(i) - 1.0) * 0.035;
        float d2 = depth + offset;
        half ring  = ringBand(d2 - travel, dydp, ringWidth);
        half spoke = ringBand(a / kTau * spokes + shear * d2,
                              spokeGrad, spokeWidth);
        ch[i] = max(ring, spoke * 0.8h);
    }

    half mask = edgeFade(coverageRadius(pos, size)) * half(amplitude) * focusMask(pos, size, focus);
    half alpha = ((ch.r + ch.g + ch.b) / 3.0h) * mask;
    // Per-channel values can exceed alpha slightly at the fringes. That
    // overshoot IS the chromatic edge; clamping it away flattens the effect.
    return half4(tint.rgb * ch * mask, alpha);
}

// MARK: - Linescape
// Nested contour rings receding to a point, line weight thinning with depth.
// The wobble term rides on `base`, so it adds ~11% to the temporal derivative;
// ReaderVisual.spectralMultiplier carries that. 3.0 x 1.15 x 0.45 = 1.55 Hz.
//
// turns 7 gives this the steepest gradient of any effect here (density x turns²
// = 147), so it is the one most dependent on ringBand's antialiasing.
[[ stitchable ]] half4 readerLinescape(float2 pos, half4 color, float4 bounds,
                                       float time, half4 tint,
                                       float speed, float amplitude, float rate,
                                       float focus) {
    float2 size = bounds.zw;
    float2 c = pos - size * 0.5;
    float r = unitRadius(pos, size);
    float halfMin = halfMinDimension(size);

    const float turns = 7.0, density = 3.0;

    float a = atan2(c.y, c.x);
    float base = convergentDepth(r, turns) * density - time * speed * rate;

    // Sum of cosines in the angle, phase-advanced by depth, so successive rings
    // are deformed differently and the stack reads as terrain rather than as
    // concentric circles.
    float wob = 0.17 * (cos(a * 2.0 + base * 1.7)
                      + cos(a * 3.0 - base * 1.1)
                      + cos(a * 5.0 + base * 0.6)) / 3.0;

    float y = base + wob;
    // Hairline at the vanishing point, heavier at the rim — Linescape's
    // lineWidth / zAdjust, expressed as a band half-width.
    float thickness = 0.05 + 0.20 * r;
    float dydp = depthGradient(r, turns, density, halfMin);

    half alpha = ringBand(y, dydp, thickness) * edgeFade(coverageRadius(pos, size)) * half(amplitude)
               * focusMask(pos, size, focus);
    return composite(tint, alpha);
}
