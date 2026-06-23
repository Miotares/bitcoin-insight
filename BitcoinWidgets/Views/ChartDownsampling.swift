//
//  ChartDownsampling.swift
//  BitcoinWidgets
//
//  Series decimation for the scrubbable history charts.
//
//  Why this exists
//  ---------------
//  Production series reach ~2185 points (3Y mempool). A ~350pt-wide chart cannot
//  resolve anywhere near that many samples — every extra point is invisible work
//  that Swift Charts still has to lay out and stroke. Worse, the old code drew an
//  AreaMark + LineMark PER point and re-ran an O(n) nearest scan on every scrub
//  tick, so a single drag rebuilt thousands of marks repeatedly.
//
//  We decimate ONCE per (data, target) change to a screen-appropriate count and
//  then use that single decimated array for BOTH the rendering AND the
//  nearest-sample lookup, so the highlighted dot always sits exactly on the drawn
//  line and the readout is always a real (date, value) sample.
//
//  Algorithm: Largest-Triangle-Three-Buckets (LTTB)
//  ------------------------------------------------
//  LTTB keeps the first and last points, splits the interior into `target-2`
//  equal buckets, and for each bucket picks the single point that forms the
//  largest-area triangle with the previously chosen point and the average of the
//  next bucket. This preserves the visual SHAPE — peaks, troughs and slopes —
//  dramatically better than naive stride/nth-point sampling, which can drop a
//  spike entirely. That visual fidelity matters here because the look (catmull-rom
//  line + flush-baseline fill) is user-approved and must not change.
//
//  Cost is O(n) and runs only when the data or target changes (memoized by the
//  caller), never per scrub tick.
//
//  iOS 17.6 compatible — pure Swift, no platform API.
//

import Foundation

enum ChartDownsampling {

    /// Decimate `points` (assumed ascending by date) to at most `target` samples
    /// using Largest-Triangle-Three-Buckets, preserving the first/last point and
    /// the overall visual shape. Returns the input unchanged when it already fits.
    ///
    /// The returned points keep their ORIGINAL `id` (their index in the full
    /// series) so identity stays stable and meaningful; callers that need the
    /// decimated array to be self-consistent for index math should rely on array
    /// position, not `id`. The scrubbable chart does exactly that (binary search
    /// over array position), so retaining original ids is purely informational and
    /// never used for indexing.
    static func lttb(_ points: [ScrubPoint], target: Int) -> [ScrubPoint] {
        let n = points.count
        // Need at least 3 buckets-worth to do anything meaningful; below the
        // target (or below 3) there is nothing to gain — return as-is.
        guard target >= 3, n > target else { return points }

        var sampled: [ScrubPoint] = []
        sampled.reserveCapacity(target)

        // Always keep the first point.
        sampled.append(points[0])

        // Width of each interior bucket. `target - 2` buckets sit between the
        // forced first and last points.
        let bucketSize = Double(n - 2) / Double(target - 2)

        // Index of the previously selected point (anchor of the triangle).
        var a = 0

        for i in 0..<(target - 2) {
            // Current bucket [rangeStart, rangeEnd) of candidate points.
            let rangeStart = Int(Double(i) * bucketSize) + 1
            var rangeEnd = Int(Double(i + 1) * bucketSize) + 1
            if rangeEnd > n - 1 { rangeEnd = n - 1 }   // never reach the forced last point

            // Average point of the NEXT bucket [avgStart, avgEnd) — the third
            // vertex of the triangle. Clamp to the valid interior range.
            let avgStart = rangeEnd
            var avgEnd = Int(Double(i + 2) * bucketSize) + 1
            if avgEnd > n { avgEnd = n }

            var avgX = 0.0
            var avgY = 0.0
            let avgCount = max(avgEnd - avgStart, 1)
            if avgEnd > avgStart {
                for j in avgStart..<avgEnd {
                    avgX += points[j].date.timeIntervalSince1970
                    avgY += points[j].value
                }
            } else {
                // Degenerate tail bucket — fall back to the last point.
                avgX = points[n - 1].date.timeIntervalSince1970
                avgY = points[n - 1].value
            }
            avgX /= Double(avgCount)
            avgY /= Double(avgCount)

            // Anchor (previously chosen) point coordinates.
            let aX = points[a].date.timeIntervalSince1970
            let aY = points[a].value

            // Pick the candidate in this bucket with the largest triangle area
            // against (anchor, next-bucket-average).
            var maxArea = -1.0
            var chosen = rangeStart
            if rangeStart < rangeEnd {
                for j in rangeStart..<rangeEnd {
                    let pX = points[j].date.timeIntervalSince1970
                    let pY = points[j].value
                    // Twice the triangle area (the constant ½ doesn't change argmax).
                    let area = abs((aX - avgX) * (pY - aY) - (aX - pX) * (avgY - aY))
                    if area > maxArea {
                        maxArea = area
                        chosen = j
                    }
                }
            } else {
                // Empty bucket (can happen when target is close to n) — keep the
                // single point at rangeStart, clamped into bounds.
                chosen = min(max(rangeStart, 1), n - 2)
            }

            sampled.append(points[chosen])
            a = chosen
        }

        // Always keep the last point.
        sampled.append(points[n - 1])
        return sampled
    }
}
