# Reader Trance Visuals: Convergent Rebuild

**Date:** 2026-08-04
**Branch:** `feature/reader-hypnotic-visuals`
**Status:** Implemented. Builds green on macOS + iOS Simulator; motion budget
verified; all six effects rendered offline and confirmed converging. Not yet
run in the app itself.

## Goal

The reader's background visuals must draw the reader's focus *into* the word at
the centre of the frame. Today they do not, and two of them actively work
against it.

## Why the current effects fail the goal

Read from `Ilumionate/TextTrance/Visuals/ReaderVisuals.metal`:

- **Tunnel** (`readerTunnel`, line 77) has its direction inverted. Its phase is
  `depth * 6.0 - time * speed * 6.0` where `depth = pow(r, 0.45)` *increases*
  outward. A constant-phase surface therefore satisfies `depth = t·speed + k`,
  so depth grows with time, so `r` grows with time. The rings expand outward.
  The effect currently pushes attention away from the word.
- **Spiral** (`readerSpiral`, line 59) is `sin(a * 5.0 + r * 9.0 - time·speed·τ)`.
  The angular term dominates the radial one, so the eye tracks arms around the
  frame tangentially. There is no inward component.
- **Drift** (`readerDrift`, line 122) places motes at a fixed radius per mote
  and modulates it with a symmetric `breath` term. Net radial displacement over
  a cycle is zero — the swarm orbits and pulses but never converges.
- **Moiré** (`readerMoire`, line 92) animates a drifting centre offset. The
  motion has no consistent direction at all.
- All four use a **linear** radius term. None reproduce the property that makes
  the reference visuals pull: feature density compressing toward a vanishing
  point.
- `centreFade` (line 28) protects word legibility but contributes nothing to
  convergence.

## Reference analysis

Source recovered from the pages themselves, not from their descriptions.

| # | Name | Technique | Convergence mechanism |
|---|------|-----------|----------------------|
| 154 | Layered Rainbow Spiral | GLSL fragment shader. `y = 1/(l + 1/turns) + ap`, `x = 1 - (floor(y) - ap)/turns`, then a two-family grid drawn in the warped space, evaluated three times with a per-channel rotation and offset | The `1/l` term compresses cells without bound toward the centre |
| 101 | Spirally Dots | three.js particle system on parametric spiral curves; `cur`/`curv` curl amounts in τ multiples, `copies` arms, grid quantisation, `vary` jitter | Particles travel along arms |
| 86 | Warp Tunnel | three.js `TubeGeometry` on a twisting spline path, camera inside the bore, four lights running its length | Camera flies through |
| 45 | Linescape | Canvas 2D. ~16 z-slices of a sum-of-cosines contour, mirrored four ways, `lineWidth` divided by depth | Nested contours rush a vanishing point |
| 13 | Eye | The classic plasma/flame fragment shader with an HSV hue rotation | **None** — organic, non-directional |

Visual 13 is deliberately not ported. It is the only reference with no
convergence, so adopting it would work against the stated goal. It can be
revisited later as a separate atmosphere option.

### Shadertoy cross-references

Three further references, source read directly from `gShaderToy.mEffect`.

**`4st3WX` — Breath Potter's Tunnel.** The most useful of the three. It arrives
at this design's core independently:

```glsl
float f = 1. / length(uv);              // ← convergentDepth, without the guard term
f += atan(uv.x, uv.y) / acos(0.);       // ← the arm shear, this spec's `+ ap`
f -= iTime;                             // ← inward: subtract time, not add
f = 1. - clamp(sin(f * PI * 2.) * dot(uv, uv) * iResolution.y / 15. + .5, 0., 1.);
f *= sin(length(uv) - .1);              // ← end-of-tunnel darkness
```

The first three lines independently confirm the primitive (§1), the arm shear
(Spiral), and the sign rule (§2). The fourth line contributes something this
spec was missing — see §4, antialiasing.

Note it omits the `+ 1/turns` guard: bare `1./length(uv)` diverges at the
centre. This spec keeps the guard, which is what makes the gradient bound in §4
finite.

**`4ds3WH` — HypnoSwirl™.** Contributes the `timeMorph` idea: a triangle wave
that *divides* the angular term, so the pattern breathes between ring-dominant
and arm-dominant character on a slow cycle.

```glsl
if (mod(activeTime, 2.0 * halfPhase) < halfPhase) timeMorph = mod(activeTime, halfPhase);
else                                             timeMorph = halfPhase - mod(activeTime, halfPhase);
timeMorph = 2.0 * timeMorph + 1.0;
float w = 0.25 + 3.0 * (sin(t + r) + 3.0 * cos(t + 5.0 * a) / timeMorph);
```

Folded into Spiral rather than added as a seventh effect, to stay inside the
agreed scope. Its other trick — multiplying two near-identical fields (`w * x`)
to square the contrast — is not adopted; it blows out highlights, which is the
wrong direction for something sitting behind text.

**`ldX3zr` — Hypnotic ripples.** The least useful of the three, and worth
recording as a counter-example rather than a source. It uses `r = -(x*x + y*y)`
— radius *squared*, so rings are widely spaced at the centre and compress
toward the **edge**, the opposite of `convergentDepth`. Its phase
`(r + t·speed)` also expands outward. It is a clean illustration of why the
radial power and the time sign are the two decisions that matter, and nothing
in it should be copied.

## Design

### 1. One shared primitive

Every effect is rebuilt on the coordinate transform from 154:

```metal
/// `turns` at r = 0, falling to ~1 at the frame edge. Feature density scales as
/// turns² toward the centre, so the middle reads as bottomless.
///
/// The `1.0 / turns` guard is load-bearing: without it the gradient diverges at
/// r = 0. With it the peak gradient is exactly `density * turns²`, which is what
/// makes the Nyquist bound in §4 computable — and, on a 1x display, binding.
static float convergentDepth(float r, float turns) {
    return 1.0 / (r + 1.0 / turns);
}
```

### 2. One inward-motion rule

```
phase = convergentDepth(r, turns) * density - time * speed * rate
```

`convergentDepth` **falls** with `r`. A constant-phase surface therefore
satisfies `convergentDepth · density = t·speed·rate + k`, so depth rises with
time, so `r` falls with time. Features move inward.

Subtracting rather than adding is the whole difference between the intended
effect and today's Tunnel bug. Every effect must use this form, and any new
effect that reverses the sign is reversing its direction of travel.

#### Why `density` is not optional

`convergentDepth` alone puts almost every ring inside the region `focusWell`
erases. At `turns = 5` the ring radii are:

```
0.800, 0.300, 0.133, 0.050, 0.000
```

Only the first two clear the well's 0.26 inner cut. The compression and the
well fight each other, and the outer two-thirds of the frame is left nearly
empty — which reads as sparse and static, not as depth.

`density` decouples *how compressed* the field is (`turns`) from *how many*
features cross it (`density`). Measured ring counts outside the well:

| density | rings outside the well | radii |
|---------|------------------------|-------|
| 1.0 | 2 | 0.800, 0.300 |
| 2.5 | 4 | 1.050, 0.633, 0.425, 0.300 |
| **4.0** | **6** | 1.133, 0.800, 0.600, 0.467, 0.371, 0.300 |
| 5.0 | 7 | 1.050, 0.800, 0.633, 0.514, 0.425, 0.356, 0.300 |

For comparison, today's `pow(r, 0.45) * 6` Tunnel yields 3 rings in the same
annulus (0.395, 0.668, 1.000), so `density = 4` is roughly double the current
visible density while keeping the compressed centre.

**`density` does not affect the safety budget.** It scales the spatial term
only; `∂phase/∂t = speed · rate` regardless of its value. Density is therefore
free to tune on device without re-deriving the frequency arithmetic.

### 3. The rule fixes the safety story too

At a fixed pixel `r` is constant, so `∂phase/∂t = speed · rate` — **independent
of radius**. The dense centre does not flicker faster than the sparse rim.

This replaces the current per-effect obligation documented at
`ReaderVisualModulation.swift:29` (`featureCount * speedBand.upperBound < 3.0`,
reasoned about separately for each shader) with a single multiplication that
holds everywhere in the frame.

### 4. Antialiasing at the vanishing point

§1 claims the finite ring count means "spatial frequency never runs away into
aliasing". That is true but marginal, and the margin needs stating rather than
assuming.

The phase gradient is bounded, and the `+ 1/turns` guard term is what bounds it:

```
y      = density / (r + 1/turns)
dy/dr  = -density / (r + 1/turns)²
peak   = |dy/dr| at r = 0  =  density · turns²
```

Converted to cycles per pixel — divide by `min(width, height) · 0.5 · scale` —
Nyquist requires the result stay under 0.5:

| target | turns=5, density=4 | turns=7, density=4 (Linescape) |
|--------|-------------------|-------------------------------|
| iPhone 17 Pro portrait (402pt @3×) | 0.166 — ok | 0.325 — ok |
| iPad 11" portrait (820pt @2×) | 0.122 — ok | 0.239 — ok |
| macOS window, Retina (500pt @2×) | 0.200 — ok | 0.392 — ok |
| **macOS small window, 1× (320pt)** | **0.625 — breaches** | **1.225 — breaches** |
| **macOS narrow, 1× (240pt)** | **0.833 — breaches** | **1.633 — breaches** |

Retina targets are comfortable. A **non-Retina macOS display with a small
window breaches Nyquist at the vanishing point**, and macOS is a first-class
platform here with a freely resizable window, so this is a real configuration
rather than a theoretical one. Aliasing there would not merely look bad: a
moiré pattern beating against the pixel grid as the rings move produces
temporal flicker that the uniform-rate argument in §3 does not cover, so this
is a safety concern and not only a quality one.

**Fix — analytic antialiasing.** `4st3WX` solves this by scaling the wave by
`dot(uv, uv) * iResolution.y / 15` before clamping: near the centre the factor
collapses to zero, the clamp resolves to a flat mid-tone, and the pattern
dissolves exactly where it would alias. That is a hand-rolled
gradient-proportional soft threshold.

Because the phase function is known in closed form, the exact version is
available and costs one divide:

```metal
/// Ring/arm band with analytic antialiasing. `dydp` is the phase change across
/// one point — what `fwidth(y)` would return, computed directly instead.
///
/// As the rings compress toward the centre `dydp` grows, the smoothstep widens
/// past the full range of `d`, and the band resolves to flat tone rather than
/// to moiré. This is what keeps the vanishing point safe on a 1x display.
static half ringBand(float y, float dydp, float thickness) {
    float d = abs(fract(y) - 0.5) * 2.0;   // 0 on the ridge, 1 between ridges
    float w = max(dydp, 0.001);
    return half(1.0 - smoothstep(thickness - w, thickness + w, d));
}

// Per effect, with halfMin = max(min(size.x, size.y) * 0.5, 1.0):
float dydp = density / (pow(r + 1.0 / turns, 2.0) * halfMin);
```

`fwidth` would also work and is more general, but is deliberately not used.
SwiftUI stitchable `colorEffect` functions are inlined into a fragment shader,
so derivatives are *probably* well-defined — but that is an implementation
detail of SwiftUI's shader compilation rather than a documented guarantee, and
derivatives are undefined under the non-uniform control flow that Drift's mote
loop contains. The closed form has neither caveat.

This replaces the fixed `smoothstep(0.35, 0.95, …)` thresholds given for each
effect in §7; those constants become the `thickness` argument.

### 5. Retuned masks

`centreFade` becomes `focusWell`; `edgeFade` is retightened. Both keep their
existing call sites and the existing 0.46 vertical squash on the well.

| mask | current | new | reason |
|------|---------|-----|--------|
| well (inner) | `smoothstep(0.35, 1.0, d)` | `smoothstep(0.26, 0.62, d)` | A tighter band gives a crisp visible rim framing the word rather than a slow gradient |
| edge (outer) | `1 - smoothstep(0.85, 1.35, r)` | `1 - smoothstep(0.78, 1.28, r)` | Dims the periphery so brightness peaks in an annulus at r ≈ 0.7 |

Together these place peak brightness in a ring around the word, with darkness
at both the centre and the corners. Combined with inward motion, the frame reads
as a field falling into the word.

### 6. Making the cap enforceable

`ReaderVisualModulation.swift:29` currently states that safety limits live in
Swift "so the caps are unit-testable and cannot be bypassed by editing a shader
constant". That is not true today: the per-effect feature counts are hardcoded
in Metal and no test sees them.

Close the gap by moving the rate into Swift and passing it as a shader argument:

```swift
extension ReaderVisual {
    /// Feature crossings per second at speed 1.0, passed to the shader as
    /// `rate`. The shader must not scale it further.
    var motionRate: Double {
        switch self {
        case .none, .breath: return 0
        case .spiral:        return 4.0
        case .tunnel:        return 4.0
        case .moire:         return 3.0
        case .drift:         return 0.5
        case .glass:         return 3.5
        case .linescape:     return 3.0
        }
    }

    /// Highest harmonic the effect's own arithmetic can produce from
    /// `motionRate`. Moiré multiplies two ring families, so their sum frequency
    /// appears in the output and must be counted.
    var spectralMultiplier: Double { self == .moire ? 2 : 1 }
}
```

A test then asserts, for **every** case in `allCases`:

```
motionRate * spectralMultiplier * ReaderVisualModulator.speedBand.upperBound < 3.0
```

Verification at `speedBand.upperBound == 0.45`:

| effect | rate | × multiplier | Hz at max speed |
|--------|------|--------------|-----------------|
| spiral | 4.0 | 4.0 | 1.80 |
| tunnel | 4.0 | 4.0 | 1.80 |
| moire | 3.0 | 6.0 | 2.70 |
| drift | 0.5 | 0.5 | 0.23 |
| glass | 3.5 | 3.5 | 1.58 |
| linescape | 3.0 | 3.0 | 1.35 |

All under 3.0 Hz.

### 7. The six effects

Shared per-effect tail: `alpha = pattern * edgeFade(r) * amplitude * focusWell(pos, size)`,
composited premultiplied against `tint` exactly as today.

`triwave(v) = 1.0 - abs(2.0 * v - 1.0)`, taken from 154. All banding goes
through `ringBand(y, dydp, thickness)` from §4, never a bare `smoothstep`.

**Spiral** — rewrite. `turns = 4`, `density = 3.5`, `arms = 3`,
`morphRate = 0.08`.
```
a  = atan2(c.y, c.x) + PI                 // 0 … τ
ap = fract(a / τ * arms)                  // position within an arm

// HypnoSwirl's timeMorph, adapted: the arm shear waxes and wanes, so the
// pattern breathes between concentric rings and a three-arm spiral.
morph = triwave(fract(time * speed * morphRate))         // 0 … 1

ring = convergentDepth(r, turns) * density - time * speed * rate
arm  = ring + ap
pattern = mix(ringBand(ring, dydp, 0.5), ringBand(arm, dydp, 0.5), morph)
```
Adding `ap` to the depth is what shears concentric rings into arms; this is
154's `y = 1/(l + 1/turns) + ap`. Arms now crawl inward instead of sweeping past.

**Crossfade the two patterns; do not scale the shear.** `ap * armWeight` looks
equivalent and is not. `ap` steps down by exactly 1 at each arm boundary, which
`fract` absorbs invisibly — but a step of `armWeight` does not divide evenly and
leaves a radial seam at every arm edge. Both patterns above are individually
seam-free, so any blend of them is too. *(Found during implementation; the
earlier `ap * armWeight` form in this spec was wrong.)*

The morph contributes `(armPattern − ringPattern) · d(morph)/dt`, bounded by
`1 × 2 × speed × morphRate = 2 × 0.45 × 0.08 = 0.072` cycles/s — well below the
1.80 Hz main term, so the §6 budget is unaffected. Cycle length at full speed is
~28 s.

**Tunnel** — direction fix plus depth curve swap. `turns = 5`, `density = 4`.
```
y = convergentDepth(r, turns) * density - time * speed * rate
pattern = ringBand(y, dydp, 0.5)
```

**Moiré** — rework for direction. `turns = 5` for both families;
`densityA = 4.0`, `densityB = 4.7`.
```
yA = convergentDepth(r, turns) * densityA - time * speed * rate
yB = convergentDepth(r, turns) * densityB - time * speed * rate
pattern = ringBand(yA, dydpA, 0.5) * ringBand(yB, dydpB, 0.5)
```
Both families converge; because they carry different ring counts across the
same compression curve, their beat envelope also travels inward. The
interference character is retained, the aimless centre-offset drift is dropped.
Varying `density` rather than `turns` keeps both families on the same
perspective, so the beat reads as one surface rather than two.

**Drift** — rework so motes converge. 40 motes retained, `turns = 5`.
```
u  = fract(hash11(i) + time * speed * rate)   // 0 = born at rim, 1 = at the well
d  = mix(1.0, turns, u)
r_mote = ((1.0 / d) - (1.0 / turns)) / (1.0 - 1.0 / turns) * 1.3
angle  = hash11(i + 37) * τ + u * winding * τ
```
Radius follows the inverse of `convergentDepth`, so motes decelerate as they
approach the centre — the perspective cue. Mote size shrinks with `u` (inward
is farther). Alpha fades in over `u < 0.1` and out over `u > 0.9` so nothing
pops into or out of existence. `winding ≈ 0.8` turns per lifetime.

Motes do not produce a repeating full-frame luminance cycle, so `motionRate`
here expresses lifetime turnover rather than feature crossings; 0.5 is well
inside budget regardless.

**Glass** *(new)* — 154's layered grid, tinted. `turns = 4`, `arms = 1`,
`gridDensity = 12`, `abb = 0.5`, `spiralAmount = 1.0`, `fuzz = 0.25`, three
channel passes. `p` is the centred position normalised by half-width.
```
// Same unwrap as Spiral, plus 154's radial coordinate `x`.
// Glass carries its own density in `gridDensity`, so the depth term is bare.
ap = fract((atan2(p.y, p.x) + PI) / τ * arms)
y  = convergentDepth(r, turns) + ap - time * speed * rate
x  = 1.0 - (floor(y) - ap) / turns          // 0 at the rim, → 1 at the centre

lineHalfWidth = 0.5 * fuzz                  // 154's grid_mm band, fixed here
for i in 0 … 2:
    adjust = 1.0 + float(i) * abb
    p2     = (p * ROTATE_45) / (1.0 + x * adjust * spiralAmount)
    c[i]   = gridLine(p2.x * gridDensity) * 0.5
           + gridLine(p2.y * gridDensity) * 0.5

// gridLine(v) = ringBand(v, gradientOfV, lineHalfWidth)
// Glass's grid is Cartesian in the warped space, so its `dydp` is the gradient
// of `p2 * gridDensity`, not the radial form used by the ring effects.
```
Dividing `p2` by a term that grows with `x` is what makes the grid squeeze into
the vanishing point; scaling that divisor per channel by `adjust` is what
separates the three channels into a chromatic fringe.

The three channel values are used as `tint.rgb * c`, so the split stays inside
the phase colour family rather than going rainbow. Alpha is the channel mean.
Per-channel values may slightly exceed alpha at the fringes — that overshoot
*is* the chromatic edge, and must be verified on device rather than clamped
away blindly.

**Linescape** *(new)* — 45 adapted from Cartesian to polar. `turns = 7`,
`density = 3`. `a = atan2(c.y, c.x)` is the frame angle in radians.
```
base = convergentDepth(r, turns) * density - time * speed * rate
wob  = 0.10 * (cos(a*2.0 + base*1.7)
             + cos(a*3.0 - base*1.1)
             + cos(a*5.0 + base*0.6)) / 3.0
y    = base + wob
w    = 0.08 + 0.5 * r                        // hairline at the vanishing point
pattern = ringBand(y, dydp, w)          // thickness IS the half-width
```
Linescape's `turns = 7` gives it the highest peak gradient of any effect
(`4 × 49 = 196`), so it is the one most dependent on §4's antialiasing. Verify
it first on a 1× display.
Nested wobbling contour rings receding to a point, line weight thinning with
depth — 45's `lineWidth ÷ zAdjust`, expressed as a smoothstep width.

## Files

| file | change |
|------|--------|
| `Ilumionate/TextTrance/Visuals/ReaderVisuals.metal` | Rewritten. ~151 → ~310 lines. Kept as one file: splitting Metal requires a shared header and build-configuration changes not justified at this size. |
| `Ilumionate/TextTrance/Visuals/ReaderVisual.swift` | Add `.glass` and `.linescape`; add `motionRate` and `spectralMultiplier`. String raw values, so persisted preferences continue to decode. |
| `Ilumionate/TextTrance/Visuals/ReaderVisualModulation.swift` | Revise the safety doc comment to describe the uniform-rate property and point at the new test. |
| `Ilumionate/TextTrance/Visuals/ReaderVisualLayer.swift` | Pass `motionRate` as a sixth `.float` shader argument. |
| `IlumionateTests/ReaderVisualTests.swift` | Extend for the two new cases. The rawValue-order assertion at line 37 will fail until updated — that failure is the guard working as intended. |
| `IlumionateTests/ReaderVisualModulatorTests.swift` | Add the motion-budget test over `allCases`. |

## Knock-on effects

- `ReaderControlSlot.effects` (`ReaderControlSlot.swift:99`) drives the Trance
  tile's `nextEffect` cycle. It goes from 5 stops to 7. No code change needed;
  worth confirming the cycle still feels usable at that length.
- `ReaderVisualControls` picker (`ReaderVisualControls.swift:107`) gains two
  entries automatically via `allCases`. Check the setup-card layout does not
  overflow with 7 items.
- `ReaderDisplayPreferences.visual` defaults to `.breath` and decodes with a
  `?? .breath` fallback (`ReaderDisplayPreferences.swift:63`), so no migration
  is required.

## Testing

Shaders cannot be unit-tested directly. Coverage is split:

**Unit (`swift-testing`):**
- Every `ReaderVisual` case has a non-empty `displayName` and `summary`.
- `shaderName` is nil exactly for `.none` and `.breath`, non-nil otherwise, and
  all shader names are unique.
- The motion budget holds for every case (section 5).
- `motionRate` is 0 exactly for the shaderless cases.

**On-device verification** (both `platform=macOS,arch=arm64` and
`platform=iOS Simulator,name=iPhone 17 Pro`, per `CLAUDE.md`):
- Each of the six effects visibly converges inward. Tunnel in particular must
  be checked against the current build to confirm the direction reversed.
- **Aliasing at the vanishing point on a 1× display**, per §4 — a non-Retina
  external monitor with the macOS window dragged narrow is the failing
  configuration, and Linescape is the effect most likely to show it. The
  annulus just outside `focusWell` must resolve to flat tone, not to a
  shimmering moiré that beats as the rings move.
- Spiral's ring↔arm morph completes a full cycle in roughly 28 s at full speed
  and does not read as a glitch at the turnaround.
- Word legibility at maximum amplitude and maximum strength.
- Frame rate with `Drift` (40-mote loop) and `Glass` (3× grid evaluation) —
  the two heaviest — at full-screen on the lowest-end target device.
- Reduce Motion pins speed to 0 and `TimelineView(paused:)` stops the schedule.

## What implementation changed

Five things in this spec turned out to be wrong or unusable once built. They are
corrected above; recorded here so the reasoning is not lost.

**1. `ringBand`'s `thickness` was inverted for two effects.** It is the band
half-width — small values give hairlines. The spec had Linescape at
`1.0 - w` and Glass at `1.0 - lineHalfWidth`, both of which produce the
*thickest* line exactly where the design calls for a hairline.

**2. A 0.5 duty cycle is far too heavy behind text.** Rendered, `thickness = 0.5`
gives fat alternating bullseye bands, and Moiré and Linescape were
indistinguishable from Tunnel. Final values: Spiral 0.26, Tunnel 0.24, Moiré
0.46 per family (their *intersection* is what reads), Linescape `0.05 + 0.20·r`.
Moiré's second density also moved from 4.7 to 6.6 — 4.0 vs 4.7 was too close to
produce a visible beat.

**3. Spiral's morph must crossfade two patterns, not scale the shear.** Covered
in §7.

**4. Glass needed rebuilding twice.**

  - As specced it did not move at all. `x = 1 - (floor(y) - ap)/turns` changes
    only when `floor(y)` steps, so time entering the radial term was quantised
    away — measured, 2 distinct values over 24 samples. **154 escapes this
    because its motion is in the angle, not the radius**, which the spec missed
    when lifting the formula.
  - Making the squeeze travel continuously — the obvious fix — breaches the
    flicker budget badly. An animated squeeze sweeps every grid line radially
    past every pixel at `p · gridDensity · adjust · spiral · π · speed · rate`,
    which is **166 Hz** at the frame corner for 154's own parameters and needs
    `gridDensity · spiral < 0.217` to stay under 3 Hz — roughly thirty times
    below anything visible.
  - A warped *Cartesian* grid also stays visually flat however hard it is
    squeezed, and does not pull the eye anywhere.

  Final form: a lattice drawn in **spiral space** — inward-travelling rings
  crossed with spokes that wind with depth — with the spokes **static in time**
  so only one family moves. That keeps it at one moving feature per unit phase,
  the same budget as Tunnel, while actually converging.

**5. Drift's motes clumped into an arc.** `hash11` over 40 motes leaves gaps
243× its own smallest, so the swarm bunched. Replaced with golden-ratio spacing
for the birth phase and √2 spacing for the angle: both badly-approximable, so
the spacing stays near-even (max/min gap 2.6 rather than 243), and being
different irrationals keeps the two decorrelated. Size and brightness still
hash — clumping there is invisible.

## Verification

- Both targets build clean: `platform=macOS,arch=arm64` and
  `platform=iOS Simulator,name=iPhone 17 Pro`.
- Motion budget checked for every case: worst is Moiré at 2.70 Hz.
- Every effect transcribed to NumPy and rendered offline. Radial
  cross-correlation over a sub-period step confirms **inward** travel for
  Spiral, Tunnel, Moiré, Glass and Linescape.
- Drift is not measurable that way — a 40-blob field gives too sparse a radial
  profile, and the metric reports noise. Checked directly instead: across 40
  motes × 400 samples, **zero** samples where a mote's radius failed to
  decrease, the only increases being the deliberate rebirths at the rim.

### Not yet done

The effects have not been seen running in the app. The offline renderer shares
the formulas, not the Metal compiler or SwiftUI's `colorEffect` plumbing, so it
cannot catch a premultiplication mistake, an argument-order mismatch, or a
`half` precision problem. Still outstanding from the testing plan: on-device
frame rate for Drift and Glass, and the 1× macOS aliasing check.

## Out of scope

- Porting visual 13 (Eye). No convergence; would fight the goal.
- Per-word reactive pulsing. Explicitly rejected in favour of keeping the
  `ReaderVisualModulator` contract at `(tint, speed, amplitude)`.
- Any change to `TextPacingEngine` or the session model.
