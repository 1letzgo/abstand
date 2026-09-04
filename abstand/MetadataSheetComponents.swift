import SwiftUI

/// Gemeinsame Bausteine der Admin-Metadaten-Sheets (Edit Metadata, Match Metadata, Edit Chapters).
///
/// Die Sheets werden aus dem Buch-Detail geöffnet und folgen deshalb dessen Design-Sprache:
/// Meta-Label-Sektion (`DetailMetaField`-Stil) → Karte (`palette.card`, `detailSectionCard*`) →
/// eingelassene Formularfelder. Kein System-`Form`/`.roundedBorder`-Chrome, alle Farben aus der
/// Appearance-Palette (`AppModel.appearancePalette`) statt aus statischen `AppTheme`-Feldern.

enum MetadataSheetMetrics {
  /// Abstand zwischen Formularzeilen innerhalb einer Karte.
  static let fieldSpacing: CGFloat = 14
  /// Innenabstand eingelassener Felder (Textfeld, Menü-Picker).
  static let fieldInsetH: CGFloat = 12
  static let fieldInsetV: CGFloat = 10
  /// Hairline um eingelassene Felder — Karte und Feld liegen sonst zu dicht beieinander.
  static let fieldBorderOpacity: Double = 0.18

  /// Kartenform der Sheets (wie `DetailDetailSectionCard`).
  static var cardShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: AppTheme.Layout.detailSectionCardCornerRadius,
      style: .continuous
    )
  }

  /// Form eingelassener Felder.
  static var fieldShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
  }
}

// MARK: - Grundgerüst

/// Scroll-Inhalt eines Metadaten-Sheets: App-Hintergrund, Tab-Ränder, lesbare Breite (iPad).
struct MetadataSheetScrollScreen<Content: View>: View {
  var spacing: CGFloat = AppTheme.Layout.sectionSpacing
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing) {
        content()
      }
      .frame(maxWidth: AppTheme.Layout.readableFormMaxWidth, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, AppTheme.Layout.tabPaddingH)
      .padding(.top, AppTheme.Layout.tabPaddingTop)
      .padding(.bottom, AppTheme.Layout.scrollBottomInsetBase)
    }
    .abstandScrollScreenBackground()
    .scrollDismissesKeyboard(.interactively)
  }
}

/// Sektionsüberschrift wie in Buch-/Folgen-Details (Versalien, `metaLabel`, optionales Symbol).
struct MetadataSheetSectionLabel: View {
  @EnvironmentObject private var model: AppModel
  let title: String

  var body: some View {
    HStack(spacing: DetailMetaLayoutMetrics.labelIconSpacing) {
      if let icon = DetailMetaLabelIcon.systemImage(for: title) {
        Image(systemName: icon)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(model.appearancePalette.textSecondary)
          .accessibilityHidden(true)
      }
      Text(title.uppercased())
        .font(DetailHeroTypography.metaLabel)
        .foregroundStyle(model.appearancePalette.textSecondary)
        .tracking(0.6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityAddTraits(.isHeader)
    .abstandThemeRefresh()
  }
}

/// Sektion: Überschrift + Inhalt (Karten, Listen) im Detail-Abstand.
struct MetadataSheetSection<Content: View>: View {
  let title: String
  var spacing: CGFloat = AppTheme.Layout.withinSectionSpacing
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      MetadataSheetSectionLabel(title: title)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Kartenfläche wie `DetailDetailSectionCard` — hier ohne Cover-Tint, da Sheets auf dem
/// neutralen App-Hintergrund liegen.
struct MetadataSheetCard<Content: View>: View {
  @EnvironmentObject private var model: AppModel
  var spacing: CGFloat = MetadataSheetMetrics.fieldSpacing
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppTheme.Layout.detailSectionCardPadding)
    .background(model.appearancePalette.card, in: MetadataSheetMetrics.cardShape)
    .abstandCardElevation(.subtle)
    .abstandThemeRefresh()
  }
}

/// Trennlinie zwischen Zeilen innerhalb einer Karte (wie Settings-Karten).
struct MetadataSheetCardDivider: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Divider()
      .overlay(model.appearancePalette.textSecondary.opacity(0.25))
      .abstandThemeRefresh()
  }
}

// MARK: - Formularzeilen

/// Eingelassene Feldfläche in Karten (Textfeld, Menü-Picker, Vorschlagslisten).
private struct MetadataSheetFieldChromeModifier: ViewModifier {
  @EnvironmentObject private var model: AppModel
  var horizontalPadding: CGFloat = MetadataSheetMetrics.fieldInsetH
  var verticalPadding: CGFloat = MetadataSheetMetrics.fieldInsetV

  func body(content: Content) -> some View {
    let palette = model.appearancePalette
    let shape = MetadataSheetMetrics.fieldShape
    return content
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(palette.background, in: shape)
      .overlay {
        shape.strokeBorder(
          palette.textSecondary.opacity(MetadataSheetMetrics.fieldBorderOpacity), lineWidth: 1)
      }
      .abstandThemeRefresh()
  }
}

extension View {
  /// Eingelassenes Feld auf einer Karte (Hintergrundfarbe + Hairline) statt System-`.roundedBorder`.
  func metadataSheetFieldChrome(
    horizontalPadding: CGFloat = MetadataSheetMetrics.fieldInsetH,
    verticalPadding: CGFloat = MetadataSheetMetrics.fieldInsetV
  ) -> some View {
    modifier(
      MetadataSheetFieldChromeModifier(
        horizontalPadding: horizontalPadding, verticalPadding: verticalPadding))
  }
}

/// Feldbeschriftung (Titel + optionaler Hinweis) über dem Eingabefeld.
struct MetadataSheetFieldLabel: View {
  @EnvironmentObject private var model: AppModel
  let title: String
  var hint: String? = nil

  var body: some View {
    let palette = model.appearancePalette
    HStack(spacing: 6) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(palette.textSecondary)
      if let hint {
        Text(hint)
          .font(.caption2)
          .foregroundStyle(palette.textSecondary.opacity(0.7))
      }
      Spacer(minLength: 0)
    }
    .accessibilityHidden(true)
    .abstandThemeRefresh()
  }
}

/// Beschriftetes Textfeld im App-Stil (Label oben, eingelassenes Feld darunter).
struct MetadataSheetTextField: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  let title: String
  @Binding var text: String
  var hint: String? = nil
  var placeholder: String? = nil
  var axis: Axis = .horizontal
  var lineLimit: ClosedRange<Int>? = nil
  var keyboardType: UIKeyboardType = .default
  var autocapitalization: TextInputAutocapitalization = .sentences
  var disablesAutocorrection: Bool = false
  var submitLabel: SubmitLabel = .done
  var onSubmit: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.labelToContentSpacing) {
      MetadataSheetFieldLabel(title: title, hint: hint)
      field
        .font(.body)
        .foregroundStyle(model.appearancePalette.textPrimary)
        .tint(themeAccent)
        .keyboardType(keyboardType)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled(disablesAutocorrection)
        .submitLabel(submitLabel)
        .onSubmit { onSubmit?() }
        .accessibilityLabel(title)
        .metadataSheetFieldChrome()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var field: some View {
    let prompt = placeholder.map {
      Text($0).foregroundStyle(model.appearancePalette.textSecondary.opacity(0.55))
    }
    if let lineLimit {
      TextField("", text: $text, prompt: prompt, axis: axis)
        .lineLimit(lineLimit)
    } else {
      TextField("", text: $text, prompt: prompt, axis: axis)
    }
  }
}

/// Beschriftetes Menü-Picker-Feld (Provider, Region) im gleichen Feld-Chrome wie Textfelder.
struct MetadataSheetMenuPicker<SelectionValue: Hashable, Options: View>: View {
  @Environment(\.themeAccent) private var themeAccent

  let title: String
  @Binding var selection: SelectionValue
  @ViewBuilder let options: () -> Options

  var body: some View {
    VStack(alignment: .leading, spacing: DetailMetaLayoutMetrics.labelToContentSpacing) {
      MetadataSheetFieldLabel(title: title)
      Picker(title, selection: $selection) {
        options()
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(themeAccent)
      .accessibilityLabel(title)
      .metadataSheetFieldChrome(verticalPadding: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Umschalter-Zeile in einer Karte (Titel + optionale Erläuterung, akzentgetönt).
struct MetadataSheetToggleRow: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.themeAccent) private var themeAccent

  let title: String
  var subtitle: String? = nil
  var subtitleLineLimit: Int? = nil
  @Binding var isOn: Bool

  var body: some View {
    let palette = model.appearancePalette
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .foregroundStyle(palette.textPrimary)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(subtitleLineLimit)
            .fixedSize(horizontal: false, vertical: subtitleLineLimit == nil)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .tint(themeAccent)
    .abstandThemeRefresh()
  }
}
