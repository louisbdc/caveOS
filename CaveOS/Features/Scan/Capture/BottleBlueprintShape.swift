import SwiftUI

/// Silhouette de bouteille bordelaise (bague, col, épaule, corps, culot) dessinée
/// proportionnellement au `rect` fourni. Symétrique par rapport à l'axe vertical.
///
/// Toutes les coordonnées restent dans les bornes du `rect` (les points de
/// contrôle des courbes du culot touchent au plus `rect.maxY`), ce qui garantit
/// un `boundingRect` contenu dans le rect — voir `BottleBlueprintShapeTests`.
struct BottleBlueprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height, cx = rect.midX

        let lipW  = w * 0.34
        let neckW = w * 0.30
        let bodyW = w * 0.92

        let topY        = rect.minY + h * 0.02   // haut de la bague
        let lipBottomY  = rect.minY + h * 0.055  // base de la bague
        let neckBottomY = rect.minY + h * 0.26   // base du col / début épaule
        let shoulderY   = rect.minY + h * 0.40   // haut du corps
        let bodyBottomY = rect.maxY - h * 0.03
        let baseInset   = h * 0.018

        let lipL = cx - lipW / 2,  lipR = cx + lipW / 2
        let neckL = cx - neckW / 2, neckR = cx + neckW / 2
        let bodyL = cx - bodyW / 2, bodyR = cx + bodyW / 2
        let shoulderCtrlY = neckBottomY + (shoulderY - neckBottomY) * 0.20

        path.move(to: CGPoint(x: lipL, y: topY))
        path.addLine(to: CGPoint(x: lipR, y: topY))                      // bague (haut)
        path.addLine(to: CGPoint(x: lipR, y: lipBottomY))               // bague (droite)
        path.addLine(to: CGPoint(x: neckR, y: lipBottomY))             // ressaut
        path.addLine(to: CGPoint(x: neckR, y: neckBottomY))            // col (droite)
        path.addQuadCurve(to: CGPoint(x: bodyR, y: shoulderY),         // épaule (droite)
                          control: CGPoint(x: bodyR, y: shoulderCtrlY))
        path.addLine(to: CGPoint(x: bodyR, y: bodyBottomY))           // corps (droite)
        path.addQuadCurve(to: CGPoint(x: bodyR - w * 0.06, y: rect.maxY - baseInset),
                          control: CGPoint(x: bodyR, y: rect.maxY))    // culot (droite)
        path.addLine(to: CGPoint(x: bodyL + w * 0.06, y: rect.maxY - baseInset)) // culot
        path.addQuadCurve(to: CGPoint(x: bodyL, y: bodyBottomY),
                          control: CGPoint(x: bodyL, y: rect.maxY))    // culot (gauche)
        path.addLine(to: CGPoint(x: bodyL, y: shoulderY))            // corps (gauche)
        path.addQuadCurve(to: CGPoint(x: neckL, y: neckBottomY),       // épaule (gauche)
                          control: CGPoint(x: bodyL, y: shoulderCtrlY))
        path.addLine(to: CGPoint(x: neckL, y: lipBottomY))           // col (gauche)
        path.addLine(to: CGPoint(x: lipL, y: lipBottomY))            // ressaut
        path.closeSubpath()
        return path
    }
}

/// Cadre rectangulaire portrait pour guider le cadrage d'une carte des vins
/// (feuille à plat). Coins arrondis, proportionnel au `rect` fourni.
struct DocumentBlueprintShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: Theme.Radius.l)
    }
}

/// Zone d'étiquette indicative (tiers central bas du corps) pour guider le cadrage.
struct LabelZoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width * 0.74
        let h = rect.height * 0.26
        let frame = CGRect(
            x: rect.midX - w / 2,
            y: rect.minY + rect.height * 0.58,
            width: w,
            height: h
        )
        return Path(roundedRect: frame, cornerRadius: Theme.Radius.s)
    }
}
