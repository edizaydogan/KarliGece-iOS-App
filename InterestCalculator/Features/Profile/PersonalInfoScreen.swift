//
//  PersonalInfoScreen.swift
//  InterestCalculator
//
//  Profil → Kişisel bilgiler: ad ve soyad. Hesap/sunucu yok; bilgiler
//  oturumla birlikte yalnız bu cihazda saklanır.
//

import SwiftUI

struct PersonalInfoScreen: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case firstName, lastName
    }

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                VStack(spacing: 10) {
                    ProfileAvatar(initials: state.profile.initials, size: 84)
                    Text(state.profile.fullName ?? "Adınız")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(state.profile.fullName == nil ? Color.slate : Color.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("Ad") {
                    TextField("Adınız", text: $state.profile.firstName)
                        .textContentType(.givenName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.ink)
                        .focused($focused, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focused = .lastName }
                        .accessibilityIdentifier("profileFirstNameField")
                }
                LabeledContent("Soyad") {
                    TextField("Soyadınız", text: $state.profile.lastName)
                        .textContentType(.familyName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.ink)
                        .focused($focused, equals: .lastName)
                        .submitLabel(.done)
                        .accessibilityIdentifier("profileLastNameField")
                }
            } footer: {
                Text("Bilgileriniz hesap ya da sunucu olmadan, yalnız bu cihazda saklanır.")
                    .foregroundStyle(.slate)
            }
            .listRowBackground(Color.drift)
        }
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .background(Color.snowfield)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("personalInfoRoot")
        .navigationTitle("Kişisel bilgiler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PersonalInfoScreen()
    }
    .environment(AppState.preview)
}
