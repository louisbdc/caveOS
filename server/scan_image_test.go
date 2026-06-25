package main

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func encodePNGBase64(t *testing.T, img image.Image) string {
	t.Helper()
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("encode png: %v", err)
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}

// tinyImageB64 renvoie un PNG 1x1 encodé base64 (image inexploitable type).
func tinyImageB64(t *testing.T) string {
	t.Helper()
	return encodePNGBase64(t, image.NewRGBA(image.Rect(0, 0, 1, 1)))
}

func TestIsUnusableImageRejectsTiny(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))
	if !isUnusableImage(encodePNGBase64(t, img)) {
		t.Fatal("une image 1x1 doit être jugée inexploitable")
	}
}

func TestIsUnusableImageRejectsUniform(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 300, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 300; x++ {
			img.Set(x, y, color.RGBA{120, 120, 120, 255})
		}
	}
	if !isUnusableImage(encodePNGBase64(t, img)) {
		t.Fatal("une image unie doit être jugée inexploitable")
	}
}

func TestIsUnusableImageAcceptsDetailed(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 300, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 300; x++ {
			img.Set(x, y, color.RGBA{uint8(x % 256), uint8(y % 256), uint8((x + y) % 256), 255})
		}
	}
	if isUnusableImage(encodePNGBase64(t, img)) {
		t.Fatal("une image détaillée (≥200px, variée) doit passer")
	}
}

func TestIsUnusableImageRejectsGarbageBase64(t *testing.T) {
	if !isUnusableImage("!!!pas-du-base64!!!") {
		t.Fatal("un base64 invalide doit être jugé inexploitable")
	}
}

// Régression : ce PNG 1x1 réel décode son EN-TÊTE (1x1) mais échoue au décodage
// complet des pixels ("too much pixel data"). Il doit quand même être rejeté via
// DecodeConfig, sinon les modèles hallucinent un vin connu sur une image vide.
func TestIsUnusableImageRejectsHeaderOnlyTinyPNG(t *testing.T) {
	const tiny = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
	if !isUnusableImage(tiny) {
		t.Fatal("un PNG 1x1 (en-tête lisible) doit être jugé inexploitable")
	}
}
