package main

import (
	"bytes"
	"encoding/base64"
	"image"
	_ "image/jpeg" // enregistre le décodeur JPEG pour image.Decode
	_ "image/png"  // enregistre le décodeur PNG pour image.Decode
	"strings"
)

// --- Garde-fou anti-hallucination (validation d'image en amont) ---------------
//
// Sur une image vide, minuscule ou unie, les modèles de vision inventent
// volontiers un vin connu (« Château Margaux ») et s'auto-déclarent confiants : le
// flag isWineLabel renvoyé par le modèle n'est donc pas fiable seul. On filtre
// donc les images manifestement inexploitables AVANT tout appel upstream, ce qui
// évite à la fois l'hallucination et des appels IA inutiles.

// minLabelDim : en deçà, l'image est trop petite pour une vraie étiquette (une
// photo d'étiquette via l'app fait ~1600 px de côté).
const minLabelDim = 200

// uniformLumRange : amplitude de luminance (0..1) en dessous de laquelle l'image
// est considérée unie/vide. Seuil très conservateur pour ne jamais rejeter une
// vraie étiquette (même sombre, son texte crée une amplitude bien supérieure).
const uniformLumRange = 0.03

// isUnusableImage renvoie true si l'image est manifestement inexploitable comme
// étiquette : base64 invalide, image trop petite, ou quasi uniforme (unie/vide).
// En cas de doute (format non décodable ici), renvoie false pour laisser les
// modèles juger — on ne bloque que les cas évidents.
func isUnusableImage(imageBase64 string) bool {
	data, err := base64.StdEncoding.DecodeString(strings.TrimSpace(imageBase64))
	if err != nil || len(data) == 0 {
		return true
	}
	// Dimensions via l'en-tête seul (DecodeConfig) : bien plus tolérant que le
	// décodage complet — certaines images valides n'exposent qu'un en-tête lisible —
	// et moins coûteux. Suffit pour rejeter une image trop petite.
	if cfg, _, cfgErr := image.DecodeConfig(bytes.NewReader(data)); cfgErr == nil {
		if cfg.Width < minLabelDim || cfg.Height < minLabelDim {
			return true
		}
	}
	// Détection d'image unie : nécessite le décodage complet des pixels. S'il échoue
	// (format non géré ici, ex. HEIC/WebP), on laisse les modèles juger.
	img, _, decErr := image.Decode(bytes.NewReader(data))
	if decErr != nil {
		return false
	}
	return isNearUniform(img)
}

// isNearUniform échantillonne une grille de l'image et renvoie true si l'amplitude
// de luminance y est négligeable (image unie/vide).
func isNearUniform(img image.Image) bool {
	b := img.Bounds()
	const grid = 16
	min, max := 1.0, 0.0
	for i := 0; i < grid; i++ {
		for j := 0; j < grid; j++ {
			x := b.Min.X + (b.Dx()*i)/grid
			y := b.Min.Y + (b.Dy()*j)/grid
			r, g, bl, _ := img.At(x, y).RGBA() // composantes 0..65535
			lum := (0.299*float64(r) + 0.587*float64(g) + 0.114*float64(bl)) / 65535
			if lum < min {
				min = lum
			}
			if lum > max {
				max = lum
			}
		}
	}
	return (max - min) < uniformLumRange
}
