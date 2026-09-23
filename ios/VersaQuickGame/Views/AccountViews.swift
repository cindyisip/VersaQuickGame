import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                BrandHeader().padding(.top, 24)
                Image("BrandMark").resizable().scaledToFit().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 24)).padding(.top, 20)
                Text("Good games.\nGood company.").font(.largeTitle.bold())
                Text("No ratings. Just your games, your people, and a little friendly competition.").font(.title3).foregroundStyle(.secondary)
                LoginForm()
                Button("Try the demo") { Task { await store.startDemo() } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Text("Explore fictional games without creating an account.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(22)
        }.background(QGTheme.background)
    }
}
struct LoginForm: View {
    @EnvironmentObject var store: AppStore
    var onSuccess: (() -> Void)?
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var sentAt: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.configured { Text("This build needs your project settings before live sign-in. The demo is ready to explore.").font(.callout).foregroundStyle(.secondary) }
            TextField("Display name", text: $name).textContentType(.nickname).textFieldStyle(.roundedBorder).disabled(codeSent).onChange(of: name) { _, v in name = String(v.prefix(60)) }
            TextField("Email address", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).disabled(codeSent)
            if codeSent {
                Text("Enter the code sent to \(email).").font(.callout).foregroundStyle(.secondary)
                TextField("Verification code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder).onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(8)) }
            }
            if let error { ErrorNotice(text: error) }
            Button {
                Task {
                    busy = true; error = nil
                    defer { busy = false }
                    do {
                        if codeSent { try await store.verify(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code, name: name); onSuccess?() }
                        else { try await store.service.sendCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines), name: name.trimmingCharacters(in: .whitespacesAndNewlines)); codeSent = true; sentAt = Date() }
                    } catch { self.error = error.localizedDescription }
                }
            } label: { if busy { ProgressView().tint(.white) } else { Text(codeSent ? "Verify & continue" : "Continue with email") } }
            .buttonStyle(PrimaryButton()).disabled(busy || !store.configured || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !email.contains("@") || (codeSent && code.count < 6))
            if codeSent {
                Button("Change email or request a new code") { if let sentAt, Date().timeIntervalSince(sentAt) < 60 { error = "Please wait a minute before requesting another code." } else { codeSent = false; code = ""; error = nil } }.font(.caption).disabled(busy)
            }
            Text("Sign in or create an account. We’ll email a verification code.").font(.caption).foregroundStyle(.secondary)
            HStack { Link("Privacy", destination: AppConfig.privacyURL); Text("·"); Link("Terms", destination: AppConfig.termsURL) }.font(.caption)
            Text("By continuing, you agree to the terms and acknowledge the privacy policy.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var clubID = ""
    @State private var newClub = ""
    @State private var deleteText = ""
    @State private var deletionPresented = false
    @State private var busy = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Your profile") { TextField("Display name", text: $name).onChange(of: name) { _, v in name = String(v.prefix(60)) } }
            Section { Picker("Default place / club", selection: $clubID) { Text("Choose each time").tag(""); ForEach(store.data?.clubs ?? []) { Text($0.name).tag($0.id) } } } header: { Text("Game defaults") } footer: { Text("New games start with this place. You can still edit the place and format for any game.") }
            Section("Saved clubs") {
                ForEach(store.data?.clubs ?? []) { club in Label(club.name, systemImage: club.id == clubID ? "checkmark.circle.fill" : "mappin.circle") }
                TextField("Add a club or playing place", text: $newClub).onChange(of: newClub) { _, v in newClub = String(v.prefix(120)) }
                Button("Add club") { Task { await run { store.data = try await store.service.addClub(name: newClub); newClub = "" } } }.disabled(newClub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
            }
            Section {
                Button(saved ? "Saved ✓" : "Save settings") { Task { await run { store.data = try await store.service.saveProfile(name: name, clubID: clubID.isEmpty ? nil : clubID); saved = true } } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { ErrorNotice(text: error) }
            }
            Section("About Versa Quick Game") {
                Link("Support & help", destination: AppConfig.supportURL)
                Link("Privacy policy", destination: AppConfig.privacyURL)
                Link("Terms of use", destination: AppConfig.termsURL)
                Text("Version 0.1 · No ratings. No DUPR connection.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(store.isDemo ? "Exit demo" : "Sign out") { Task { await store.signOut() } }
                Button(store.isDemo ? "Delete demo data" : "Delete my account", role: .destructive) { deletionPresented = true }
            }
        }
        .navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { name = store.displayName; clubID = store.data?.profile.default_club_id ?? "" }
        .sheet(isPresented: $deletionPresented) {
            NavigationStack {
                Form {
                    Section { Text(store.isDemo ? "This removes fictional demo data from this device." : "This permanently deletes your account, games you hosted, saved clubs, and groups. Your claimed spots in games hosted by other people become anonymous. This cannot be undone.") }
                    Section { TextField("Type DELETE", text: $deleteText).textInputAutocapitalization(.characters).autocorrectionDisabled(); Button("Delete permanently", role: .destructive) { Task { await run { try await store.deleteAccount(); dismiss() } } }.disabled(deleteText != "DELETE" || busy); if let error { ErrorNotice(text: error) } }
                }.navigationTitle("Delete account").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { deletionPresented = false; deleteText = "" } } }
            }
        }
    }
    @MainActor private func run(_ work: () async throws -> Void) async { busy = true; error = nil; defer { busy = false }; do { try await work() } catch { self.error = error.localizedDescription } }
}
