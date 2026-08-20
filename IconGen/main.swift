import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green:   CGFloat((v >> 8) & 0xFF) / 255,
            blue:    CGFloat(v & 0xFF) / 255, alpha: a)
}

func ctx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ img: CGImage, _ path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                              UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

func radial(_ c: CGContext, _ center: CGPoint, _ r: CGFloat, _ colors: [CGColor], _ locs: [CGFloat]) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locs)!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
}

func rays(_ c: CGContext, _ center: CGPoint, inner: CGFloat, outer: CGFloat,
          count: Int, width: CGFloat, color: CGColor) {
    c.saveGState(); c.setFillColor(color)
    for i in 0..<count {
        let a = .pi / 8 + CGFloat(i) * (.pi * 2 / CGFloat(count))
        let d = CGPoint(x: cos(a), y: sin(a)), p = CGPoint(x: -sin(a), y: cos(a))
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: center.x + d.x*inner + p.x*width,     y: center.y + d.y*inner + p.y*width))
        path.addLine(to: CGPoint(x: center.x + d.x*inner - p.x*width,     y: center.y + d.y*inner - p.y*width))
        path.addLine(to: CGPoint(x: center.x + d.x*outer - p.x*width*0.45, y: center.y + d.y*outer - p.y*width*0.45))
        path.addLine(to: CGPoint(x: center.x + d.x*outer + p.x*width*0.45, y: center.y + d.y*outer + p.y*width*0.45))
        path.closeSubpath()
        c.addPath(path); c.fillPath()
    }
    c.restoreGState()
}

/// "Monitor Ring" — sun inside a battery-charge arc.
///
/// `pt` is the *logical* size the rendition represents, `px` the pixel size to
/// draw at. Detail is chosen from `pt` so that a 16pt icon stays simple even
/// when rendered at 32px for retina.
func monitorRing(px: CGFloat, pt: CGFloat) -> CGImage {
    let c = ctx(Int(px), Int(px))
    let inset = px * 0.094
    let box = CGRect(x: inset, y: inset, width: px - inset*2, height: px - inset*2)
    let sq = CGPath(roundedRect: box, cornerWidth: box.width*0.2237,
                    cornerHeight: box.width*0.2237, transform: nil)

    let tiny  = pt <= 16
    let small = pt <= 32

    // background
    c.saveGState(); c.addPath(sq); c.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [hex(0x1B3B5F), hex(0x0E1E33)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(bg, start: CGPoint(x: box.minX, y: box.maxY),
                         end: CGPoint(x: box.maxX, y: box.minY), options: [])

    let cen = CGPoint(x: box.midX, y: box.midY)

    // Ring gets proportionally fatter and the sun larger as the icon shrinks,
    // otherwise both vanish into a smudge.
    let ringR = box.width * (tiny ? 0.300 : small ? 0.298 : 0.295)
    let lw    = box.width * (tiny ? 0.135 : small ? 0.105 : 0.072)
    let sunR  = box.width * (tiny ? 0.115 : small ? 0.120 : 0.108)

    // track
    c.setStrokeColor(hex(0xFFFFFF, tiny ? 0.20 : 0.13))
    c.setLineWidth(lw); c.setLineCap(.round)
    c.addArc(center: cen, radius: ringR, startAngle: 0, endAngle: .pi*2, clockwise: false)
    c.strokePath()

    // 72% charge arc
    c.saveGState()
    c.setLineWidth(lw); c.setLineCap(.round)
    c.addArc(center: cen, radius: ringR, startAngle: .pi/2,
             endAngle: .pi/2 - .pi*2*0.72, clockwise: true)
    c.replacePathWithStrokedPath()
    c.clip()
    let arc = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [hex(0xF6D32D), hex(0x2EC27E)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(arc, start: CGPoint(x: box.minX, y: box.maxY),
                         end: CGPoint(x: box.maxX, y: box.minY), options: [])
    c.restoreGState()

    // sun — glow and rays are noise below ~128pt, so they drop out
    if !small {
        radial(c, cen, box.width*0.24, [hex(0xF6D32D, 0.30), hex(0xF6D32D, 0)], [0, 1])
    }
    if !tiny {
        let rayW = box.width * (small ? 0.030 : 0.021)
        rays(c, cen, inner: sunR*1.5, outer: sunR*(small ? 1.92 : 2.02),
             count: 8, width: rayW, color: hex(0xF6D32D))
    }
    c.saveGState()
    c.addEllipse(in: CGRect(x: cen.x-sunR, y: cen.y-sunR, width: sunR*2, height: sunR*2))
    c.clip()
    if tiny {
        c.setFillColor(hex(0xF9DC4A))
        c.fill(CGRect(x: cen.x-sunR, y: cen.y-sunR, width: sunR*2, height: sunR*2))
    } else {
        radial(c, CGPoint(x: cen.x-sunR*0.2, y: cen.y+sunR*0.28), sunR*2,
               [hex(0xFFF6C9), hex(0xF6D32D), hex(0xEFA531)], [0, 0.55, 1])
    }
    c.restoreGState()
    c.restoreGState()

    return c.makeImage()!
}

// ------------------------------------------------------------------ output

let dir = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "sheet"

if mode == "iconset" {
    let set = "\(dir)/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    // (filename, pixel size, logical size)
    let renditions: [(String, CGFloat, CGFloat)] = [
        ("icon_16x16.png",        16,   16),
        ("icon_16x16@2x.png",     32,   16),
        ("icon_32x32.png",        32,   32),
        ("icon_32x32@2x.png",     64,   32),
        ("icon_128x128.png",     128,  128),
        ("icon_128x128@2x.png",  256,  128),
        ("icon_256x256.png",     256,  256),
        ("icon_256x256@2x.png",  512,  256),
        ("icon_512x512.png",     512,  512),
        ("icon_512x512@2x.png", 1024, 1024),
    ]
    for (name, px, pt) in renditions {
        writePNG(monitorRing(px: px, pt: pt), "\(set)/\(name)")
    }
    print("wrote \(renditions.count) renditions to \(set)")
} else {
    // Actual-size row, plus a 6x nearest-neighbour blowup of the small ones.
    let actual: [(CGFloat, CGFloat)] = [(256,256), (128,128), (64,32), (32,32), (16,16)]
    let zoomed: [(CGFloat, CGFloat)] = [(32,32), (16,16)]
    let pad: CGFloat = 24
    let w = pad + actual.reduce(0) { $0 + $1.0 + pad } + 200*2 + pad*2
    let h = 256 + pad*2
    let sheet = ctx(Int(w), Int(h))
    sheet.setFillColor(hex(0xF2F2F2)); sheet.fill(CGRect(x: 0, y: 0, width: w, height: h))
    sheet.interpolationQuality = .none
    var x = pad
    for (px, pt) in actual {
        sheet.draw(monitorRing(px: px, pt: pt),
                   in: CGRect(x: x, y: pad + (256-px)/2, width: px, height: px))
        x += px + pad
    }
    for (px, pt) in zoomed {
        sheet.draw(monitorRing(px: px, pt: pt), in: CGRect(x: x, y: pad + 28, width: 200, height: 200))
        x += 200 + pad
    }
    writePNG(sheet.makeImage()!, "\(dir)/c-refined.png")
    print("wrote \(dir)/c-refined.png")
}
