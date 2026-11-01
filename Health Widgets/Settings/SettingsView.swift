import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsReconnect = false
    @State private var confirmDisconnect = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                if model.isDemo {
                    Section {
                        Label("Mode démo : les données sont générées sur l'iPhone.", systemImage: "sparkles")
                        Button("Connecter une vraie montre") { model.signOut() }
                    } header: {
                        Text("Compte")
                    }
                } else {
                    Section("Montres connectées") {
                        if model.connections.isEmpty {
                            Text("Aucune connexion").foregroundStyle(.secondary)
                        }
                        ForEach(model.connections) { connection in
                            ConnectionRow(connection: connection)
                        }
                        Button("Reconnecter Garmin") { showsReconnect = true }
                        Button("Déconnecter Garmin", role: .destructive) { confirmDisconnect = true }
                    }

                    Section {
                        LabeledContent("Adresse", value: model.serverURL?.absoluteString ?? "–")
                        Button("Changer de serveur") { model.signOut() }
                    } header: {
                        Text("Serveur de synchronisation")
                    } footer: {
                        Text("Votre mot de passe Garmin n'est jamais stocké. Le serveur conserve uniquement des jetons d'accès chiffrés, qui se renouvellent automatiquement.")
                    }

                    Section {
                        Button("Supprimer mon compte et mes données", role: .destructive) { confirmDelete = true }
                        if let deleteError {
                            Text(deleteError).font(.footnote).foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Supprime les jetons Garmin et les données en cache sur le serveur, puis réinitialise l'app.")
                    }
                }

                Section("À propos") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Link(destination: URL(string: "https://github.com/cyberjunky/python-garminconnect")!) {
                        Label("Données Garmin via python-garminconnect", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Application indépendante, non affiliée à Garmin Ltd. Les informations affichées ne constituent pas un avis médical.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Réglages")
            .task { await model.loadConnections() }
            .refreshable { await model.loadConnections() }
            .sheet(isPresented: $showsReconnect, onDismiss: { Task { await model.loadConnections() } }) {
                ReconnectGarminSheet()
            }
            .confirmationDialog("Déconnecter Garmin ?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Déconnecter", role: .destructive) { Task { await model.disconnect(.garmin) } }
            } message: {
                Text("Les jetons Garmin seront supprimés du serveur. Les widgets n'afficheront plus de données.")
            }
            .confirmationDialog("Supprimer le compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) {
                    Task {
                        do {
                            try await model.deleteServerAccount()
                        } catch {
                            deleteError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Cette action est irréversible.")
            }
        }
    }
}

struct ConnectionRow: View {
    var connection: ConnectionInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title3)
                .foregroundStyle(MetricKind.bodyBattery.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.provider.displayName).font(.headline)
                if let name = connection.fullName ?? connection.displayName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                if let last = connection.lastSuccessAt {
                    Text("Dernière synchro \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(connection.needsReauth ? "Reconnexion requise" : "Connecté")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill((connection.needsReauth ? Color.orange : MetricKind.readiness.tint).opacity(0.18)))
                .foregroundStyle(connection.needsReauth ? Color.orange : MetricKind.readiness.tint)
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
