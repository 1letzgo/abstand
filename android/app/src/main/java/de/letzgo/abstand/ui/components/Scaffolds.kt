package de.letzgo.abstand.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.LocalScrollBottomInset
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme

// Screen-Gerüste je Kategorie (CLAUDE.md „Design-Grundlagen“):
// Tab-Root → TabRootScaffold · Detailseite → DetailScaffold · Settings-Unterseite →
// SettingsSubpageScaffold · Sheet → MetadataSheetScaffold / AbstandSheet (Overlays.kt) ·
// Vollbild-Overlay → eigenes Layout mit Theme.palette.background.

/** iOS: `abstandScrollScreenBackground()` — App-Hintergrund (`palette.background`). */
fun Modifier.abstandScrollScreenBackground(): Modifier = composed { background(Theme.palette.background) }

/** iOS: `AppThemeScreenBackground` — füllt die Fläche mit `palette.background`. */
@Composable
fun AppThemeScreenBackground(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(Theme.palette.background))
}

/**
 * iOS: `abstandDetailScrollBackground(_:)` — Palette-Hintergrund, darüber der Cover-Tint
 * (Dark: voll, Light: 52 %), über die ganze Fläche inkl. Systemleisten.
 */
fun Modifier.abstandDetailScrollBackground(tint: Color): Modifier = composed {
    val palette = Theme.palette
    val overlay = if (palette.isDarkLike) tint else tint.copy(alpha = tint.alpha * 0.52f)
    drawBehind {
        drawRect(palette.background)
        drawRect(overlay)
    }
}

/** Unterer Scroll-Abstand: `scrollBottomInsetBase` + Mini-Player-Inset ([LocalScrollBottomInset]). */
@Composable
fun abstandScrollBottomPadding(): Dp = AppTheme.Layout.scrollBottomInsetBase + LocalScrollBottomInset.current

/** Zurück-Pfeil für Top-App-Bars (Android-Ersatz für den iOS-Back-Button). */
@Composable
fun AbstandBackButton(onBack: () -> Unit, tint: Color = Theme.palette.textPrimary) {
    AbstandIconButton(Icons.AutoMirrored.Filled.ArrowBack, "Back", onClick = onBack, tint = tint)
}

/**
 * iOS: Tab-Root (`.toolbarTitleDisplayMode(.inlineLarge)` + `abstandTabScreenChrome()` +
 * `AbstandFixedBrowseStripSectionsLayout`). Feste M3-`TopAppBar` (64 dp, Titel `titleLarge`): der
 * Titel steht von Anfang an in der Leiste (wie `.inlineLarge`), kein Ein-/Ausklappen; [header] = fixer Browse-Strip unter dem Titel (bleibt stehen).
 * [content] bekommt das fertige Content-Padding (Top-Bar, `tabPaddingH`, Abstand Titel →
 * Inhalt, unterer Mini-Player-Inset) und soll es an seine `LazyColumn`/`LazyVerticalGrid` geben.
 * Die NavigationBar gehört der Tab-Shell; hier keine Bottom-Insets.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TabRootScaffold(
    title: String,
    modifier: Modifier = Modifier,
    actions: (@Composable RowScope.() -> Unit)? = null,
    header: (@Composable () -> Unit)? = null,
    content: @Composable (PaddingValues) -> Unit,
) {
    val palette = Theme.palette
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = palette.background,
        contentColor = palette.textPrimary,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            if (header != null) {
                // Keine Titelzeile (der Tab-Name steht in der Navigation Bar): die Bereichs-Pills sind
                // die Top-Leiste, die Aktionen (Filter, Sortieren, …) stehen rechts in derselben Zeile.
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(palette.background)
                        .windowInsetsPadding(WindowInsets.statusBars)
                        // Gleiche Kopfzeilenhöhe in allen Tabs (Pills, Tabs, Überschrift, Aktionen).
                        .heightIn(min = AppTheme.Layout.minTapTarget)
                        .padding(end = if (actions != null) AppTheme.Layout.tightSpacing else AppTheme.Layout.tabPaddingH - AppTheme.Layout.stackSpacing)
                        .semantics { heading(); contentDescription = title },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f)) { header() }
                    if (actions != null) {
                        CompositionLocalProvider(LocalContentColor provides Theme.accent) {
                            Row(verticalAlignment = Alignment.CenterVertically, content = actions)
                        }
                    }
                }
            } else {
                TopAppBar(
                    title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    actions = actions ?: {},
                    scrollBehavior = scrollBehavior,
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = palette.background,
                        scrolledContainerColor = palette.scheme.surfaceContainer,
                        titleContentColor = palette.textPrimary,
                        actionIconContentColor = Theme.accent,
                    ),
                )
            }
        },
    ) { inner ->
        content(
            PaddingValues(
                start = AppTheme.Layout.tabPaddingH,
                end = AppTheme.Layout.tabPaddingH,
                top = inner.calculateTopPadding() + AppTheme.Layout.tabTitleToHeaderBlockSpacing,
                bottom = abstandScrollBottomPadding(),
            ),
        )
    }
}

/**
 * iOS: gepushte Detailseite (Titel `""` + `.inline`, Header im Content,
 * `abstandDetailScrollBackground(coverTint)`). Transparente Inline-`TopAppBar` mit Zurück-Pfeil
 * und [actions]; Hintergrund = Palette + Cover-Tint über die ganze Fläche. [content] bekommt
 * das Padding (Top-Bar + Mini-Player-Inset, **ohne** horizontales Padding — Hero-Bilder laufen
 * randlos; Textblöcke setzen `tabPaddingH` selbst).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScaffold(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    coverTint: Color = Color.Transparent,
    title: String = "",
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit,
) {
    val palette = Theme.palette
    Scaffold(
        modifier = modifier.abstandDetailScrollBackground(coverTint),
        containerColor = Color.Transparent,
        contentColor = palette.textPrimary,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { AbstandBackButton(onBack) },
                actions = actions,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    scrolledContainerColor = Color.Transparent,
                    titleContentColor = palette.textPrimary,
                    navigationIconContentColor = palette.textPrimary,
                    actionIconContentColor = palette.textPrimary,
                ),
            )
        },
    ) { inner ->
        content(PaddingValues(top = inner.calculateTopPadding(), bottom = abstandScrollBottomPadding()))
    }
}

/**
 * iOS: Settings-Unterseite (`ServerAdminScrollScreen`, Titel gesetzt + `.inline`). Inline-
 * `TopAppBar` mit Titel und Zurück-Pfeil; Inhalt als `LazyColumn` (iOS: `ScrollView` +
 * `LazyVStack`) mit `tabPaddingH`, oben `withinSectionSpacing`, unten Mini-Player-Inset,
 * Sektionen im Abstand [spacing] (Standard `sectionSpacing`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSubpageScaffold(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},
    spacing: Dp = AppTheme.Layout.sectionSpacing,
    state: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit,
) {
    val palette = Theme.palette
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = palette.background,
        contentColor = palette.textPrimary,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { AbstandBackButton(onBack) },
                actions = actions,
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = palette.background,
                    scrolledContainerColor = palette.scheme.surfaceContainer,
                    titleContentColor = palette.textPrimary,
                    navigationIconContentColor = palette.textPrimary,
                    actionIconContentColor = Theme.accent,
                ),
            )
        },
    ) { inner ->
        LazyColumn(
            state = state,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = AppTheme.Layout.tabPaddingH,
                end = AppTheme.Layout.tabPaddingH,
                top = inner.calculateTopPadding() + AppTheme.Layout.withinSectionSpacing,
                bottom = abstandScrollBottomPadding(),
            ),
            verticalArrangement = Arrangement.spacedBy(spacing),
            content = content,
        )
    }
}

/**
 * Bestätigen-Aktion in Sheet-Top-Bars (iOS: `.confirmationAction`) — Akzent-Text, bei
 * [isBusy] ein Inline-Spinner.
 */
@Composable
fun SheetConfirmAction(label: String, onClick: () -> Unit, enabled: Boolean = true, isBusy: Boolean = false) {
    if (isBusy) {
        Box(Modifier.padding(horizontal = AppTheme.Layout.screenPadding)) { AbstandInlineSpinner() }
    } else {
        AbstandTextButton(label, onClick, enabled = enabled, emphasized = true)
    }
}

/**
 * iOS: Sheet (Titel + `.inline`, cancel/confirm-Toolbar, `MetadataSheetScrollScreen`).
 * Android: Material-Vollbild-Dialog — ✕ links ([onCancel]), Titel, Bestätigen rechts
 * ([onConfirm] `null` = keine Bestätigung). Inhalt scrollt, lesbare Breite
 * `readableFormMaxWidth`, Ränder `tabPaddingH`/`tabPaddingTop`, Abstand [spacing].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MetadataSheetScaffold(
    title: String,
    onCancel: () -> Unit,
    onConfirm: (() -> Unit)? = null,
    confirmLabel: String = "Save",
    confirmEnabled: Boolean = true,
    isBusy: Boolean = false,
    spacing: Dp = AppTheme.Layout.sectionSpacing,
    content: @Composable ColumnScope.() -> Unit,
) {
    Dialog(
        onDismissRequest = onCancel,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        val palette = Theme.palette
        Scaffold(
            containerColor = palette.background,
            contentColor = palette.textPrimary,
            topBar = {
                TopAppBar(
                    title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    navigationIcon = {
                        AbstandIconButton(SF.xmark, "Cancel", onClick = onCancel, tint = palette.textPrimary)
                    },
                    actions = { if (onConfirm != null) SheetConfirmAction(confirmLabel, onConfirm, confirmEnabled, isBusy) },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = palette.background,
                        scrolledContainerColor = palette.scheme.surfaceContainer,
                        titleContentColor = palette.textPrimary,
                    ),
                )
            },
        ) { inner ->
            Box(
                Modifier.fillMaxSize().padding(inner).imePadding().verticalScroll(rememberScrollState()),
                contentAlignment = Alignment.TopCenter,
            ) {
                Column(
                    Modifier
                        .widthIn(max = AppTheme.Layout.readableFormMaxWidth)
                        .fillMaxWidth()
                        .padding(
                            start = AppTheme.Layout.tabPaddingH,
                            end = AppTheme.Layout.tabPaddingH,
                            top = AppTheme.Layout.tabPaddingTop,
                            bottom = AppTheme.Layout.scrollBottomInsetBase,
                        ),
                    verticalArrangement = Arrangement.spacedBy(spacing),
                    content = content,
                )
            }
        }
    }
}
