package de.letzgo.abstand.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.abstand.data.AbsApiClient
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.CoverImageTier
import de.letzgo.abstand.data.absPlainText
import de.letzgo.abstand.logic.BooksEntityDetailNav
import de.letzgo.abstand.logic.CatalogLogic
import de.letzgo.abstand.model.AppModel
import de.letzgo.abstand.model.EntityDetailLoader
import de.letzgo.abstand.model.EntityDetailState
import de.letzgo.abstand.model.LibraryBookCardStyle
import de.letzgo.abstand.store.CoverImageCache
import de.letzgo.abstand.ui.AppTheme
import de.letzgo.abstand.ui.IosType
import de.letzgo.abstand.ui.LocalTabNavigator
import de.letzgo.abstand.ui.SF
import de.letzgo.abstand.ui.Theme
import de.letzgo.abstand.ui.bold
import de.letzgo.abstand.ui.components.AbstandInlineSpinner
import de.letzgo.abstand.ui.components.AbstandLoadingSpinner
import de.letzgo.abstand.ui.components.AbstandSectionEmptyState
import de.letzgo.abstand.ui.components.CoverImage
import de.letzgo.abstand.ui.components.CoverImageContentMode
import de.letzgo.abstand.ui.components.DetailScaffold
import de.letzgo.abstand.ui.components.LocalCoverEnvironment
import de.letzgo.abstand.ui.components.SquareCoverImage
import de.letzgo.abstand.ui.library.LibraryBookListCard
import de.letzgo.abstand.ui.library.coverRevisionFor
import de.letzgo.abstand.ui.semibold
import kotlinx.coroutines.launch

/** iOS: `entityPlaceholderIcon`. */
private val BooksEntityDetailNav.Kind.placeholderIcon: ImageVector
    get() = when (this) {
        BooksEntityDetailNav.Kind.AUTHOR -> SF.personCropCircle
        BooksEntityDetailNav.Kind.SERIES -> SF.booksVertical
        BooksEntityDetailNav.Kind.NARRATOR -> SF.waveform
        BooksEntityDetailNav.Kind.COLLECTION -> SF.folder
        BooksEntityDetailNav.Kind.GENRE -> SF.sparkles
        BooksEntityDetailNav.Kind.TAG -> SF.tag
    }

/** Autor/Serie bekommen Cover + Tint; Sprecher, Genre, Tag, Sammlung nur den Titelblock (iOS: `usesPlainDetailBackground`). */
private val BooksEntityDetailNav.Kind.usesPlainBackground: Boolean
    get() = this == BooksEntityDetailNav.Kind.NARRATOR || this == BooksEntityDetailNav.Kind.GENRE ||
        this == BooksEntityDetailNav.Kind.TAG || this == BooksEntityDetailNav.Kind.COLLECTION

/**
 * iOS: `BooksEntityDetailView` — Autor (Foto rund, Beschreibung, Bücher nach Serien gruppiert),
 * Serie (erstes Band als Cover, Lesereihenfolge), Sammlung (Beschreibung), Sprecher/Genre/Tag
 * (gefilterte Liste mit Paging). Pull-to-Refresh; Bücher immer als kompakte Zeilen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BooksEntityDetailScreen(nav: BooksEntityDetailNav, onBack: (() -> Unit)? = null, model: AppModel = AppModel.shared) {
    val navigator = LocalTabNavigator.current
    val back: () -> Unit = onBack ?: { navigator?.pop() }
    val loader = remember(nav.id) { EntityDetailLoader(nav, model) }
    val state by loader.state.collectAsState()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(nav.id) { loader.reload() }

    val env = LocalCoverEnvironment.current
    val catalog = model.catalog
    // Header-Tint (iOS: `loadHeaderTint`) — Autorenfoto bzw. Hero-Cover des ersten Bands.
    val firstBook = state.books.firstOrNull()
    val (tintUrl, tintKey) = when {
        nav.kind == BooksEntityDetailNav.Kind.AUTHOR -> catalog.authorImageURL(nav.entityId) to
            CoverImageCache.cacheKey("entity:author:${nav.entityId}#cover-hero", env.revision)
        nav.kind == BooksEntityDetailNav.Kind.SERIES && firstBook != null ->
            env.serverBaseURL?.let { AbsApiClient.itemCoverURL(it, firstBook.id, CoverImageTier.hero) } to
                CoverImageCache.cacheKey(CoverImageCache.scopeId(firstBook.id, CoverImageTier.hero), coverRevisionFor(firstBook.updatedAt))
        else -> null to null
    }
    val tint = rememberDetailCoverTint(tintUrl, tintKey)
    val background = if (nav.kind.usesPlainBackground) Theme.palette.background else tint.background

    DetailScaffold(onBack = back, coverTint = background) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    try {
                        loader.reload()
                    } finally {
                        refreshing = false
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = AppTheme.Layout.tabPaddingH, end = AppTheme.Layout.tabPaddingH,
                    top = padding.calculateTopPadding() + AppTheme.Layout.withinSectionSpacing,
                    bottom = padding.calculateBottomPadding(),
                ),
                verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing),
            ) {
                item(key = "header") { EntityHeader(nav, state, model) }
                if (nav.kind == BooksEntityDetailNav.Kind.AUTHOR || nav.kind == BooksEntityDetailNav.Kind.COLLECTION) {
                    item(key = "description") { EntityDescription(state) }
                }
                if (nav.kind == BooksEntityDetailNav.Kind.AUTHOR) {
                    authorGroupedBooks(state)
                } else {
                    flatBooks(state, onAppear = { id -> loader.loadMoreIfNeeded(id) })
                }
            }
        }
    }
}

@Composable
private fun EntityHeader(nav: BooksEntityDetailNav, state: EntityDetailState, model: AppModel) {
    val palette = Theme.palette
    val count = when {
        state.total > 0 -> state.total
        state.books.isNotEmpty() -> state.books.size
        state.loading -> nav.numBooks
        else -> null
    }
    Column(Modifier.fillMaxWidth().padding(bottom = AppTheme.Layout.sectionSpacing - AppTheme.Layout.withinSectionSpacing), verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.rowSpacing)) {
        if (!nav.kind.usesPlainBackground) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { EntityCover(nav, state, model) }
        }
        Column(verticalArrangement = Arrangement.spacedBy(AppTheme.Layout.compactSpacing)) {
            Text(nav.title, style = IosType.title2.bold, color = palette.textPrimary, modifier = Modifier.fillMaxWidth())
            Text(nav.filterSummaryPrefix, style = IosType.subheadline.semibold, color = Theme.accent)
            CatalogLogic.bookCountLabel(count)?.let { Text(it, style = IosType.subheadline, color = palette.textSecondary) }
        }
    }
}

/** iOS: `entityCover` — Autor: rundes Foto (80 % Breite); Serie: erstes Band im Hero-Rahmen. */
@Composable
private fun EntityCover(nav: BooksEntityDetailNav, state: EntityDetailState, model: AppModel) {
    val palette = Theme.palette
    when (nav.kind) {
        BooksEntityDetailNav.Kind.AUTHOR -> BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(Modifier.width(maxWidth * 0.8f).aspectRatio(1f).clip(CircleShape).background(palette.card), contentAlignment = Alignment.Center) {
                Icon(nav.kind.placeholderIcon, null, tint = palette.textSecondary, modifier = Modifier.size(48.dp))
                CoverImage(
                    url = model.catalog.authorImageURL(nav.entityId),
                    cacheScopeId = "entity:author:${nav.entityId}#cover-hero",
                    cacheRevision = LocalCoverEnvironment.current.revision,
                    contentMode = CoverImageContentMode.Fill,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        else -> {
            val book = state.books.firstOrNull()
            DetailHeroCoverFrame {
                if (book != null) {
                    SquareCoverImage(itemId = book.id, tier = CoverImageTier.hero, cacheRevision = coverRevisionFor(book.updatedAt), modifier = Modifier.fillMaxSize())
                } else {
                    Box(Modifier.fillMaxSize().background(palette.card), contentAlignment = Alignment.Center) {
                        Icon(nav.kind.placeholderIcon, null, tint = palette.textSecondary, modifier = Modifier.size(48.dp))
                    }
                }
            }
        }
    }
}

/** iOS: `entityDescriptionSection` — Spinner bis Meta bereit, dann „DESCRIPTION  Text". */
@Composable
private fun EntityDescription(state: EntityDetailState) {
    val palette = Theme.palette
    if (!state.metaReady) {
        Box(Modifier.padding(vertical = AppTheme.Layout.tightSpacing)) { AbstandInlineSpinner() }
        return
    }
    val text = absPlainText(state.description).ifEmpty { "—" }
    Row(horizontalArrangement = Arrangement.spacedBy(AppTheme.Layout.withinSectionSpacing)) {
        Text("DESCRIPTION", style = IosType.caption.bold, color = palette.textSecondary, modifier = Modifier.width(AppTheme.Layout.metaLabelColumnWidth))
        Text(text, style = IosType.subheadline, color = palette.textPrimary, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun EntitySectionHeading(title: String) {
    Text(title.uppercase(), style = IosType.caption.bold, color = Theme.palette.textSecondary, modifier = Modifier.fillMaxWidth())
}

/** iOS: `AuthorDetailBookListCard` — immer kompakte Zeile; Cover mittig beschnitten (außer reine eBooks). */
@Composable
private fun EntityBookCard(book: AbsBook) {
    LibraryBookListCard(book, LibraryBookCardStyle.compact, forceCompact = true, usesSquareCenterCropCover = !book.isPureEbookLibraryItem)
}

/** iOS: `authorGroupedBooksSection` — je Serie eine Gruppe, dann „Books"/„Other books". */
private fun LazyListScope.authorGroupedBooks(state: EntityDetailState) {
    val sections = state.authorSeriesSections
    val standalone = state.authorStandaloneBooks
    val isEmpty = sections.isEmpty() && standalone.isEmpty()
    when {
        state.loading && isEmpty -> item(key = "loading") { AbstandLoadingSpinner() }
        isEmpty -> item(key = "empty") { AbstandSectionEmptyState("No books found.") }
        else -> {
            sections.forEach { s ->
                item(key = "series-head-${s.id}") { Box(Modifier.padding(top = AppTheme.Layout.sectionSpacing - AppTheme.Layout.withinSectionSpacing)) { EntitySectionHeading(s.name) } }
                items(s.books, key = { "series-${s.id}-${it.id}" }) { EntityBookCard(it) }
            }
            if (standalone.isNotEmpty()) {
                item(key = "standalone-head") {
                    Box(Modifier.padding(top = AppTheme.Layout.sectionSpacing - AppTheme.Layout.withinSectionSpacing)) {
                        EntitySectionHeading(if (sections.isEmpty()) "Books" else "Other books")
                    }
                }
                items(standalone, key = { "standalone-${it.id}" }) { EntityBookCard(it) }
            }
        }
    }
}

/** iOS: `flatEntityDetailBooksSection` — „Books" + Zeilen, Paging am Ende (Filter-basierte Listen). */
private fun LazyListScope.flatBooks(state: EntityDetailState, onAppear: suspend (String) -> Unit) {
    item(key = "books-head") { EntitySectionHeading("Books") }
    when {
        state.loading && state.books.isEmpty() -> item(key = "loading") { AbstandLoadingSpinner() }
        state.books.isEmpty() -> item(key = "empty") { AbstandSectionEmptyState("No books found.") }
        else -> items(state.books, key = { "book-${it.id}" }) { book ->
            EntityBookCard(book)
            LaunchedEffect(book.id) { onAppear(book.id) }
        }
    }
}

/** iOS: Autor-Detail. */
@Composable
fun AuthorDetailScreen(authorId: String, title: String? = null, numBooks: Int? = null, libraryId: String? = null) =
    BooksEntityDetailScreen(BooksEntityDetailNav(BooksEntityDetailNav.Kind.AUTHOR, authorId, title?.trim()?.ifEmpty { null } ?: "Author", numBooks, libraryId))

/** iOS: Serien-Detail. */
@Composable
fun SeriesDetailScreen(seriesId: String, title: String? = null, numBooks: Int? = null, libraryId: String? = null) =
    BooksEntityDetailScreen(BooksEntityDetailNav(BooksEntityDetailNav.Kind.SERIES, seriesId, title?.trim()?.ifEmpty { null } ?: "Series", numBooks, libraryId))

/** iOS: Sammlungs-Detail. */
@Composable
fun CollectionDetailScreen(collectionId: String, title: String? = null, numBooks: Int? = null, libraryId: String? = null) =
    BooksEntityDetailScreen(
        BooksEntityDetailNav(BooksEntityDetailNav.Kind.COLLECTION, collectionId, title?.trim()?.ifEmpty { null } ?: "Collection", numBooks, libraryId),
    )

/** iOS: Sprecher-Detail (Name = ID). */
@Composable
fun NarratorDetailScreen(name: String, numBooks: Int? = null, libraryId: String? = null) =
    BooksEntityDetailScreen(BooksEntityDetailNav(BooksEntityDetailNav.Kind.NARRATOR, name.trim(), name.trim(), numBooks, libraryId))

/** iOS: Genre-/Tag-Detail (gefilterte Bücherliste). [kind] = `GENRE` oder `TAG`. */
@Composable
fun FacetFilteredBooksScreen(kind: BooksEntityDetailNav.Kind, value: String, numBooks: Int? = null, libraryId: String? = null) =
    BooksEntityDetailScreen(BooksEntityDetailNav(kind, value.trim(), value.trim(), numBooks, libraryId))
