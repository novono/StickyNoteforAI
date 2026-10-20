import AppKit

struct PaperAppearance: Equatable {
  enum Corner: Int, CaseIterable { case lowerRight, lowerLeft, upperRight, upperLeft }
  let corner: Corner
  let curlWidth: CGFloat
  let curlHeight: CGFloat
  let backLightness: CGFloat
  let shadowOpacity: CGFloat
  let shadowBlur: CGFloat
  let creaseStrength: CGFloat
  let tilt: CGFloat
  let arrivalDuration: TimeInterval
  let removalDuration: TimeInterval
  let grainOffset: Int
  var onLeft: Bool { corner == .lowerLeft || corner == .upperLeft }
  var onTop: Bool { corner == .upperLeft || corner == .upperRight }

  init(id: String) {
    // Stable across launches and independent of Swift's randomized Hasher.
    var state: UInt64 = 14_695_981_039_346_656_037
    for byte in id.utf8 { state = (state ^ UInt64(byte)) &* 1_099_511_628_211 }
    func next() -> CGFloat {
      state &+= 0x9e37_79b9_7f4a_7c15
      var x = state
      x = (x ^ (x >> 30)) &* 0xbf58_476d_1ce4_e5b9
      x = (x ^ (x >> 27)) &* 0x94d0_49bb_1331_11eb
      x ^= x >> 31
      return CGFloat(x >> 11) / CGFloat(UInt64(1) << 53)
    }
    _ = next()  // Keep each note's other material variations stable.
    corner = .lowerRight
    curlWidth = 10 + next() * 11
    curlHeight = 9 + next() * 12
    backLightness = 0.12 + next() * 0.17
    shadowOpacity = 0.10 + next() * 0.10
    shadowBlur = 2 + next() * 3
    creaseStrength = 0.08 + next() * 0.10
    tilt = (next() * 0.045 + 0.045) * (corner == .lowerLeft || corner == .upperLeft ? 1 : -1)
    arrivalDuration = 0.44 + Double(next()) * 0.10
    removalDuration = 0.51 + Double(next()) * 0.10
    grainOffset = Int(next() * 999)
  }
  func cornerPoint(_ point: NSPoint, size: NSSize) -> NSPoint {
    NSPoint(x: onLeft ? size.width - point.x : point.x, y: onTop ? size.height - point.y : point.y)
  }
  func foldLine(size: NSSize, amount: CGFloat) -> (a: CGFloat, b: CGFloat, c: CGFloat) {
    let offset = (onLeft ? size.width : 0) - (onTop ? size.height : 0)
    return (onLeft ? -1 : 1, onTop ? 1 : -1, size.width - amount - offset)
  }
}
