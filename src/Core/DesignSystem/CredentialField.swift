import SwiftUI

/// The credential input (DESIGN.md "Input"): a visible label above the field -- never
/// placeholder-only -- with a secure variant that has NO reveal control. A stored sender key
/// is never re-rendered (D-10): while `savedIndicator` is set and the field is untouched, its
/// text appears in place of a value and the bound string stays empty. The fill is opaque --
/// nothing translucent or blurred sits behind it.
struct CredentialField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var savedIndicator: String? = nil
    var footnote: String? = nil

    @FocusState private var isFocused: Bool
    @State private var hasBeenEdited = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        label: String,
        text: Binding<String>,
        isSecure: Bool = false,
        savedIndicator: String? = nil,
        footnote: String? = nil
    ) {
        self.label = label
        self._text = text
        self.isSecure = isSecure
        self.savedIndicator = savedIndicator
        self.footnote = footnote
    }

    /// True while a saved credential's indicator stands in for a value: secure, an indicator
    /// was supplied, and nothing has been typed to replace it yet. Never true once the field
    /// has been touched, so a value never gets silently masked back to a stale indicator.
    private var showsSavedIndicator: Bool {
        isSecure && savedIndicator != nil && !hasBeenEdited && text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.spacingBase) {
            Text(label)
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                .accessibilityHidden(true)

            fieldRow
                .frame(maxWidth: .infinity, minHeight: DSMetrics.minTapTarget)
                .padding(.horizontal, DSMetrics.spacingBase)
                .background(DSPalette.body.background(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: DSMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(DSPalette.secondary.foreground(for: colorScheme))
                )
                .clipShape(RoundedRectangle(cornerRadius: DSMetrics.cornerRadius, style: .continuous))

            if let footnote {
                Text(footnote)
                    .dsFont(.secondary)
                    .foregroundStyle(DSPalette.secondary.foreground(for: colorScheme))
            }
        }
    }

    @ViewBuilder
    private var fieldRow: some View {
        if showsSavedIndicator {
            HStack(spacing: DSMetrics.spacingBase) {
                Image(systemName: "checkmark.circle.fill")
                Text(savedIndicator ?? "")
                    .dsFont(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
            .contentShape(Rectangle())
            .onTapGesture {
                hasBeenEdited = true
                isFocused = true
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(savedIndicator ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to replace")
        } else if isSecure {
            SecureField("", text: $text)
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($isFocused)
                .accessibilityLabel(label)
                .onChange(of: text) { _, _ in hasBeenEdited = true }
        } else {
            TextField("", text: $text)
                .dsFont(.body)
                .foregroundStyle(DSPalette.body.foreground(for: colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($isFocused)
                .accessibilityLabel(label)
        }
    }
}

private struct CredentialFieldPreviewStack: View {
    @State private var plainValue = "https://example.invalid/webhook"
    @State private var secureValue = ""
    @State private var secureWithSavedValue = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSMetrics.groupGap) {
                CredentialField(
                    label: "Webhook URL",
                    text: $plainValue,
                    footnote: "Where pings are sent."
                )
                CredentialField(
                    label: "Sender key",
                    text: $secureValue,
                    isSecure: true
                )
                CredentialField(
                    label: "Sender key",
                    text: $secureWithSavedValue,
                    isSecure: true,
                    savedIndicator: "Key saved"
                )
            }
            .padding(DSMetrics.screenMargin)
        }
    }
}

#Preview("Light — default") {
    CredentialFieldPreviewStack()
}

#Preview("Dark — default") {
    CredentialFieldPreviewStack()
        .preferredColorScheme(.dark)
}

#Preview("Light — AX5") {
    CredentialFieldPreviewStack()
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark — AX5") {
    CredentialFieldPreviewStack()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
