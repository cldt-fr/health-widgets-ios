import SwiftUI

/// Welcome → provider → server → Garmin sign-in → (MFA code) → dashboard.
struct OnboardingFlow: View {
    enum Step: Hashable {
        case providers
        case server
        case garmin
        case code(challengeID: String)
    }

    @Environment(AppModel.self) private var model
    @State private var path: [Step] = Self.debugPath

    /// DEBUG: `-onboardingStep code` opens a step directly (screenshots, layout checks).
    private static var debugPath: [Step] {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "onboardingStep") {
        case "server": return [.providers, .server]
        case "garmin": return [.providers, .server, .garmin]
        case "code": return [.providers, .server, .garmin, .code(challengeID: "debug")]
        default: return []
        }
        #else
        return []
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onConnect: { path.append(.providers) },
                onDemo: { model.startDemo() }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .providers:
                    ProviderPickerView { path.append(.server) }
                case .server:
                    ServerSetupView { path.append(.garmin) }
                case .garmin:
                    GarminLoginView { result in
                        switch result {
                        case .connected: model.finishOnboarding()
                        case .needsCode(let challengeID): path.append(.code(challengeID: challengeID))
                        }
                    }
                case .code(let challengeID):
                    GarminCodeView(challengeID: challengeID) { model.finishOnboarding() }
                }
            }
        }
        .tint(MetricKind.bodyBattery.tint)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    var onConnect: () -> Void
    var onDemo: () -> Void

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 28) {
                Spacer(minLength: 20)
                HeroRings()
                    .frame(width: 230, height: 230)
                VStack(spacing: 12) {
                    Text("Vos données de montre,\nen widgets sublimes.")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("Body Battery, sommeil, VFC, disposition à l'entraînement… directement sur votre écran d'accueil et votre écran verrouillé.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                ProviderStrip()
                Spacer(minLength: 12)
                VStack(spacing: 12) {
                    Button(action: onConnect) {
                        Label("Connecter ma montre", systemImage: "applewatch.radiowaves.left.and.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    Button(action: onDemo) {
                        Text("Explorer avec des données de démo")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(24)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Three concentric gradient rings filling up: the app's signature.
struct HeroRings: View {
    @State private var progress: [Double] = [0, 0, 0]

    private let kinds: [MetricKind] = [.bodyBattery, .sleep, .readiness]
    private let targets: [Double] = [0.82, 0.68, 0.9]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.085
            ZStack {
                ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                    RingGauge(progress: progress[index], colors: kind.colors, lineWidth: line)
                        .padding(CGFloat(index) * (line + side * 0.03))
                }
                Image(systemName: "heart.fill")
                    .font(.system(size: side * 0.16, weight: .semibold))
                    .foregroundStyle(MetricKind.heartRate.gradient)
                    .symbolEffect(.breathe, options: .repeating)
            }
            .frame(width: side, height: side)
        }
        .onAppear {
            for index in kinds.indices {
                withAnimation(.spring(duration: 1.4, bounce: 0.25).delay(0.15 * Double(index))) {
                    progress[index] = targets[index]
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProviderStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([ProviderID.garmin, .polar, .coros, .suunto], id: \.self) { provider in
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(provider.isAvailable ? 0.12 : 0.05)))
                    .foregroundStyle(provider.isAvailable ? .primary : .secondary)
            }
        }
    }
}

// MARK: - Provider

struct ProviderPickerView: View {
    var onGarmin: () -> Void

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Quelle est votre montre ?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.bottom, 6)
                    ForEach(ProviderID.allCases.filter { $0 != .demo }) { provider in
                        Button {
                            if provider == .garmin { onGarmin() }
                        } label: {
                            ProviderRow(provider: provider)
                        }
                        .buttonStyle(.plain)
                        .disabled(!provider.isAvailable)
                    }
                    Text("D'autres marques arrivent : le serveur est conçu pour accueillir plusieurs fournisseurs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProviderRow: View {
    var provider: ProviderID

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(provider.isAvailable ? AnyShapeStyle(MetricKind.bodyBattery.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "applewatch")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(provider.isAvailable ? .white : .secondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).font(.headline)
                Text(provider.isAvailable ? String(localized: "Garmin Connect : toutes les métriques") : String(localized: "Bientôt disponible"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: provider.isAvailable ? "chevron.right" : "clock")
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface(tint: provider.isAvailable ? MetricKind.bodyBattery.tint : nil, cornerRadius: 20)
        .opacity(provider.isAvailable ? 1 : 0.55)
    }
}

// MARK: - Server

struct ServerSetupView: View {
    var onReady: () -> Void

    @Environment(AppModel.self) private var model
    @State private var address = SharedSettings().serverURL?.absoluteString ?? SharedSettings.defaultServerURL?.absoluteString ?? ""
    @State private var signupCode = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        OnboardingForm(
            title: "Votre serveur",
            subtitle: "L'adresse et le code d'inscription de votre serveur Health Widgets (voir le README). Garmin n'est contacté que par lui.",
            symbol: "server.rack"
        ) {
            FieldCard {
                TextField("http://192.168.1.20:8000", text: $address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Divider()
                SecureField("Code d'inscription (si configuré)", text: $signupCode)
                    .textInputAutocapitalization(.never)
            }
            if let error { ErrorText(error) }
            PrimaryButton(title: "Continuer", isWorking: isWorking, isEnabled: url != nil) {
                Task { await submit() }
            }
        }
    }

    private var url: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    private func submit() async {
        guard let url else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.prepareServer(url: url, signupCode: signupCode)
            error = nil
            onReady()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Garmin

struct GarminLoginView: View {
    var onResult: (AppModel.GarminStep) -> Void

    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var isChina = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        OnboardingForm(
            title: "Garmin Connect",
            subtitle: "Votre mot de passe sert une seule fois à obtenir un jeton d'accès. Il n'est jamais stocké, ni sur l'iPhone ni sur le serveur.",
            symbol: "lock.shield"
        ) {
            FieldCard {
                TextField("E-mail Garmin", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Divider()
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                Divider()
                Toggle("Compte Garmin Chine (garmin.cn)", isOn: $isChina)
                    .font(.subheadline)
            }
            if let error { ErrorText(error) }
            PrimaryButton(title: "Se connecter", isWorking: isWorking, isEnabled: email.contains("@") && !password.isEmpty) {
                Task { await submit() }
            }
            if isWorking {
                Text("Connexion à Garmin… cela peut prendre jusqu'à une minute.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let step = try await model.connectGarmin(email: email.trimmingCharacters(in: .whitespaces), password: password, isChina: isChina)
            password = ""
            error = nil
            onResult(step)
        } catch {
            self.error = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? APIError else { return error.localizedDescription }
        switch error.code {
        case "invalid_credentials": return String(localized: "E-mail ou mot de passe incorrect (ou compte verrouillé).")
        case "invalid_mfa_code": return String(localized: "Code incorrect. Vérifiez le dernier code reçu.")
        case "mfa_challenge_expired": return String(localized: "Le code a expiré. Recommencez la connexion.")
        default: return error.errorDescription ?? String(localized: "Erreur inconnue")
        }
    }
}

struct GarminCodeView: View {
    var challengeID: String
    var onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var lastSubmitted = ""
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingForm(
            title: "Code de vérification",
            subtitle: "Garmin vient de vous envoyer un code à usage unique (e-mail ou SMS). Touchez la suggestion au-dessus du clavier, ou copiez le code puis touchez Coller.",
            symbol: "number.square"
        ) {
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($focused)
                .padding(.vertical, 14)
                .cardSurface(tint: MetricKind.bodyBattery.tint, cornerRadius: 20)
                .onChange(of: code) { _, value in
                    code = Self.sanitized(value)
                    // Garmin codes have 6 digits: send as soon as one is typed, pasted or
                    // filled in by iOS, once per code.
                    if code.count == 6, code != lastSubmitted, !isWorking {
                        lastSubmitted = code
                        Task { await submit() }
                    }
                }
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first, let found = Self.code(in: text) { code = found }
            }
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
            if let error { ErrorText(error) }
            PrimaryButton(title: "Valider", isWorking: isWorking, isEnabled: code.count >= 4) {
                Task { await submit() }
            }
        }
        .onAppear { focused = true }
    }

    /// Digits only, at most 8. Also undoes an iOS autofill that inserts the code twice.
    static func sanitized(_ value: String) -> String {
        var digits = String(value.filter(\.isNumber))
        if digits.count == 12, digits.prefix(6) == digits.suffix(6) { digits = String(digits.prefix(6)) }
        return String(digits.prefix(8))
    }

    /// The code inside a pasted message ("Your security code is 123456").
    static func code(in text: String) -> String? {
        text.firstMatch(of: /\d{4,8}/).map { String($0.output) }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.submitGarminCode(challengeID: challengeID, code: code)
            onDone()
        } catch {
            self.error = GarminLoginView.message(for: error)
        }
    }
}

// MARK: - Building blocks

struct OnboardingForm<Content: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(MetricKind.bodyBattery.gradient)
                        .padding(14)
                        .background(Circle().fill(MetricKind.bodyBattery.tint.opacity(0.15)))
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    content
                }
                .padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FieldCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .cardSurface(cornerRadius: 20)
    }
}

struct PrimaryButton: View {
    var title: LocalizedStringKey
    var isWorking: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isWorking ? 0 : 1)
                if isWorking { ProgressView().tint(.white) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .disabled(!isEnabled || isWorking)
        .sensoryFeedback(.impact(weight: .light), trigger: isWorking)
    }
}

struct ErrorText: View {
    var message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(hex: 0xFF6B6B))
    }
}

#Preview {
    OnboardingFlow().environment(AppModel())
}
