import SwiftUI

/// Documentation in-app des codes d'erreur courants affichés par les caves à vin
/// (codes génériques HH/LL/EE + variantes par marque).
struct HardwareCodesView: View {
    var body: some View {
        List {
            Section {
                ForEach(HardwareErrorCode.generic) { code in
                    HardwareCodeRow(code: code)
                }
            } header: {
                Text("Codes génériques")
            } footer: {
                Text("La plupart des caves électroniques partagent ces affichages.")
            }

            ForEach(HardwareBrandCodes.all) { brand in
                Section(brand.name) {
                    ForEach(brand.codes) { code in
                        HardwareCodeRow(code: code)
                    }
                }
            }

            Section {
                Label(
                    "En cas de doute, débranche la cave 5 minutes puis rebranche-la avant d'appeler le SAV. Conserve les bouteilles à l'abri de la lumière et de la chaleur.",
                    systemImage: "lightbulb"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                Text("Conseil")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Codes erreur")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Ligne

private struct HardwareCodeRow: View {
    let code: HardwareErrorCode

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text(code.code)
                    .font(.headline.monospaced().weight(.bold))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(code.severity.color, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                StatusBadge(
                    text: code.severity.label,
                    color: code.severity.color,
                    systemImage: code.severity.symbol
                )
            }

            Text(code.meaning)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(code.actions.enumerated()), id: \.offset) { _, action in
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(action)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Modèle de données (statique, embarqué)

enum HardwareSeverity {
    case warning
    case critical
    case info

    var label: String {
        switch self {
        case .warning: return "Avertissement"
        case .critical: return "Critique"
        case .info: return "Information"
        }
    }

    var color: Color {
        switch self {
        case .warning: return .orange
        case .critical: return Theme.wine
        case .info: return .blue
        }
    }

    var symbol: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct HardwareErrorCode: Identifiable {
    let id = UUID()
    let code: String
    let meaning: String
    let actions: [String]
    let severity: HardwareSeverity

    static let generic: [HardwareErrorCode] = [
        HardwareErrorCode(
            code: "HH",
            meaning: "Température trop haute par rapport à la consigne.",
            actions: [
                "Vérifie que la porte est bien fermée et le joint intact.",
                "Éloigne la cave des sources de chaleur et laisse 5 cm d'aération.",
                "Laisse 24 h pour revenir à la consigne ; si l'alerte persiste, contacte le SAV (compresseur ou sonde)."
            ],
            severity: .critical
        ),
        HardwareErrorCode(
            code: "LL",
            meaning: "Température trop basse par rapport à la consigne.",
            actions: [
                "Contrôle que la température ambiante n'est pas inférieure à la plage de fonctionnement.",
                "Vérifie le réglage de consigne (souvent modifié par erreur).",
                "En cas de gel, débranche et fais contrôler le thermostat."
            ],
            severity: .critical
        ),
        HardwareErrorCode(
            code: "EE",
            meaning: "Défaut de sonde de température (capteur déconnecté ou défectueux).",
            actions: [
                "Redémarre la cave (débranche 5 min).",
                "Si le code revient, la sonde doit être remplacée : contacte le SAV.",
                "Surveille manuellement la température avec un thermomètre en attendant."
            ],
            severity: .critical
        ),
        HardwareErrorCode(
            code: "E1 / E2",
            meaning: "Erreur capteur (E1 : sonde supérieure, E2 : sonde inférieure sur les caves multi-zones).",
            actions: [
                "Identifie la zone concernée.",
                "Redémarre l'appareil.",
                "Remplacement de sonde par un technicien si persistant."
            ],
            severity: .warning
        ),
        HardwareErrorCode(
            code: "dF / DEF",
            meaning: "Cycle de dégivrage en cours (normal sur certaines caves).",
            actions: [
                "Aucune action : attends la fin du cycle.",
                "Si l'eau s'accumule, vérifie l'évacuation des condensats."
            ],
            severity: .info
        )
    ]
}

struct HardwareBrandCodes: Identifiable {
    let id = UUID()
    let name: String
    let codes: [HardwareErrorCode]

    static let all: [HardwareBrandCodes] = [
        HardwareBrandCodes(
            name: "La Sommelière",
            codes: [
                HardwareErrorCode(
                    code: "HtA",
                    meaning: "Alarme haute température (équivalent HH).",
                    actions: [
                        "Vérifie porte, joint et ventilation.",
                        "Patiente 24 h ; appelle le SAV si l'alarme reste affichée."
                    ],
                    severity: .critical
                ),
                HardwareErrorCode(
                    code: "LtA",
                    meaning: "Alarme basse température (équivalent LL).",
                    actions: [
                        "Vérifie la température ambiante de la pièce.",
                        "Contrôle la consigne réglée."
                    ],
                    severity: .warning
                )
            ]
        ),
        HardwareBrandCodes(
            name: "Climadiff",
            codes: [
                HardwareErrorCode(
                    code: "P1",
                    meaning: "Défaut de la sonde de température ambiante.",
                    actions: [
                        "Redémarre l'appareil.",
                        "Remplacement de sonde si le code persiste."
                    ],
                    severity: .warning
                ),
                HardwareErrorCode(
                    code: "P2",
                    meaning: "Défaut de la sonde d'évaporateur.",
                    actions: [
                        "Contacte le SAV : intervention technique requise."
                    ],
                    severity: .critical
                )
            ]
        ),
        HardwareBrandCodes(
            name: "Vintec",
            codes: [
                HardwareErrorCode(
                    code: "rt",
                    meaning: "Défaut de sonde de température de la pièce.",
                    actions: [
                        "Vérifie le placement de la cave.",
                        "Réinitialise l'appareil ; SAV si nécessaire."
                    ],
                    severity: .warning
                ),
                HardwareErrorCode(
                    code: "AH / AL",
                    meaning: "Alarme température haute (AH) ou basse (AL).",
                    actions: [
                        "Contrôle porte et environnement.",
                        "Vérifie la consigne et laisse stabiliser."
                    ],
                    severity: .critical
                )
            ]
        ),
        HardwareBrandCodes(
            name: "EuroCave",
            codes: [
                HardwareErrorCode(
                    code: "Témoin clignotant",
                    meaning: "Anomalie détectée (température hors plage ou défaut technique).",
                    actions: [
                        "Consulte l'écran de diagnostic intégré.",
                        "Note le code affiché et contacte le service EuroCave."
                    ],
                    severity: .warning
                ),
                HardwareErrorCode(
                    code: "Alarme sonore",
                    meaning: "Porte ouverte trop longtemps ou dérive de température prolongée.",
                    actions: [
                        "Referme la porte et vérifie le joint magnétique.",
                        "Si l'alarme persiste fermée, fais contrôler le groupe froid."
                    ],
                    severity: .critical
                )
            ]
        )
    ]
}

#Preview {
    NavigationStack {
        HardwareCodesView()
    }
}
