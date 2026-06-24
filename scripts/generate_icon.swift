import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Génère l'icône d'app CaveOS (1024×1024) : verre de vin doré sur fond bordeaux.
let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("contexte")
}

// Origine en haut-gauche (y vers le bas).
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let wine     = color(0.45, 0.07, 0.13)
let wineDark = color(0.22, 0.04, 0.08)
let wineMid  = color(0.34, 0.05, 0.10)
let liquid   = color(0.58, 0.09, 0.17)
let liquidDk = color(0.40, 0.05, 0.11)
let gold     = color(0.86, 0.69, 0.36)
let goldDk   = color(0.66, 0.49, 0.22)
let goldLite = color(0.96, 0.84, 0.55)

// 1) Fond : dégradé diagonal bordeaux.
let bg = CGGradient(colorsSpace: cs, colors: [wineMid, wineDark] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(S), y: CGFloat(S)), options: [])

// 2) Halo doré radial derrière le verre.
let glow = CGGradient(colorsSpace: cs, colors: [color(0.86, 0.69, 0.36, 0.30), color(0.86, 0.69, 0.36, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 470), endRadius: 430, options: [])

// 2b) Vignette : assombrit les coins pour donner de la profondeur.
let vignette = CGGradient(colorsSpace: cs, colors: [color(0, 0, 0, 0), color(0.10, 0.01, 0.03, 0.55)] as CFArray, locations: [0.55, 1])!
ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 740, options: [])

let cx: CGFloat = 512

// Verre légèrement agrandi et centré.
ctx.translateBy(x: 512, y: 520)
ctx.scaleBy(x: 1.12, y: 1.12)
ctx.translateBy(x: -512, y: -520)

// Chemin intérieur du bol (pour clipper le liquide).
func bowlInterior() -> CGMutablePath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 366, y: 332))
    p.addCurve(to: CGPoint(x: 512, y: 566), control1: CGPoint(x: 364, y: 474), control2: CGPoint(x: 424, y: 566))
    p.addCurve(to: CGPoint(x: 658, y: 332), control1: CGPoint(x: 600, y: 566), control2: CGPoint(x: 660, y: 474))
    p.addLine(to: CGPoint(x: 366, y: 332))
    p.closeSubpath()
    return p
}

// 3) Liquide dans le bol, clippé.
ctx.saveGState()
ctx.addPath(bowlInterior())
ctx.clip()
let liq = CGGradient(colorsSpace: cs, colors: [liquid, liquidDk] as CFArray, locations: [0, 1])!
let liquidTop: CGFloat = 408
ctx.drawLinearGradient(liq, start: CGPoint(x: cx, y: liquidTop), end: CGPoint(x: cx, y: 566), options: [])
// Surface du vin (ellipse claire).
ctx.setFillColor(color(0.66, 0.12, 0.20).copy(alpha: 0.9)!)
ctx.fillEllipse(in: CGRect(x: cx - 140, y: liquidTop - 16, width: 280, height: 32))
ctx.restoreGState()

// 4) Contour du verre (or), tracé épais arrondi.
ctx.setStrokeColor(gold)
ctx.setLineWidth(20)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Bol.
let bowl = CGMutablePath()
bowl.move(to: CGPoint(x: 366, y: 332))
bowl.addCurve(to: CGPoint(x: 512, y: 566), control1: CGPoint(x: 364, y: 474), control2: CGPoint(x: 424, y: 566))
bowl.addCurve(to: CGPoint(x: 658, y: 332), control1: CGPoint(x: 600, y: 566), control2: CGPoint(x: 660, y: 474))
ctx.addPath(bowl)
ctx.strokePath()

// Rim (ellipse d'ouverture).
ctx.strokeEllipse(in: CGRect(x: cx - 146, y: 332 - 30, width: 292, height: 60))

// Pied (tige).
let stem = CGMutablePath()
stem.move(to: CGPoint(x: cx, y: 566))
stem.addLine(to: CGPoint(x: cx, y: 716))
ctx.addPath(stem)
ctx.strokePath()

// Base.
let foot = CGMutablePath()
foot.move(to: CGPoint(x: 392, y: 726))
foot.addQuadCurve(to: CGPoint(x: 632, y: 726), control: CGPoint(x: cx, y: 752))
ctx.addPath(foot)
ctx.strokePath()

// 5) Reflet doré clair sur le bol (gauche).
ctx.setStrokeColor(goldLite.copy(alpha: 0.55)!)
ctx.setLineWidth(8)
let shine = CGMutablePath()
shine.move(to: CGPoint(x: 410, y: 360))
shine.addCurve(to: CGPoint(x: 430, y: 510), control1: CGPoint(x: 392, y: 420), control2: CGPoint(x: 398, y: 470))
ctx.addPath(shine)
ctx.strokePath()

// 6) Liseré doré subtil interne (cadre arrondi) pour la finition.
_ = goldDk

guard let image = ctx.makeImage() else { fatalError("image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("destination")
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("écrit: \(outPath)")
} else {
    fatalError("finalize")
}
