package de.letzgo.abstand.model

import de.letzgo.abstand.data.AbsAuthorShelfEntity
import de.letzgo.abstand.data.AbsBook
import de.letzgo.abstand.data.AbsItemsInProgressPayload
import de.letzgo.abstand.data.AbsLibrarySeriesListItem
import de.letzgo.abstand.data.AbsPodcastEpisodeListItem
import de.letzgo.abstand.data.AbsStartShelfLocalization
import de.letzgo.abstand.data.AbsStartShelfSection
import de.letzgo.abstand.data.AbsUserMediaProgress
import de.letzgo.abstand.data.swiftTrim

/** Eine Zeile der Home-Regal-Einstellungen (iOS: `startSettingsCategoryList`-Tupel). */
data class StartCategoryRow(val category: String, val label: String)

/**
 * Kontext für „gehört das in Continue listening?“ (iOS: `progressByItemId`,
 * `isProgressKeyBlockedFromContinueListening`, `isActivelyPlayingMedia`).
 */
data class ContinueContext(
    val progress: Map<String, AbsUserMediaProgress>,
    /** Unterdrückte/verworfene/lokal fertig markierte Keys. */
    val blockedKeys: Set<String> = emptySet(),
    /** `progressLookupKey` des gerade geladenen Mediums. */
    val activeKey: String? = null,
) {
    fun lastUpdate(key: String): Long = progress[key]?.lastUpdate ?: 0
}

/**
 * Reine Home-Regal-Logik aus `AppModel.swift` (Start-Dashboard, Continue listening, Regal-Reihenfolge,
 * ausgeschaltete Kategorien, Home-Browse-Kategorie). Ohne Zustand und ohne Android — alles, was iOS
 * aus dem Model liest, kommt als Parameter herein (testbar, [HomeStore] hält den Zustand).
 */
object HomeShelfLogic {
    /** iOS: `homeContinueCategory` — einziges Regal für „Continue listening“. */
    const val homeContinueCategory = "recentlyListened"
    const val newestEpisodesCategory = "newestEpisodes"
    const val continueEbooksCategory = "continueEbooks"
    private const val legacyFallbackCategory = "itemsInProgressFallback"

    /** iOS: `continueListeningMinPositionSeconds` — kein Continue für bloße Klicks. */
    const val continueListeningMinPositionSeconds = 2.0

    // MARK: - Kategorien ein/aus, Reihenfolge

    /** iOS: `normalizedStartSettingsCategory`. */
    fun normalizedCategory(category: String): String =
        if (category == legacyFallbackCategory) homeContinueCategory else category

    /** iOS: `migrateStartDisabledCategoriesIfNeeded` — `null` = nichts zu tun. */
    fun migratedDisabledCategories(disabled: Set<String>): Set<String>? {
        if (legacyFallbackCategory !in disabled) return null
        return disabled - legacyFallbackCategory + homeContinueCategory
    }

    /** iOS: `isStartCategoryEnabled`. */
    fun isEnabled(category: String, disabled: Set<String>): Boolean = normalizedCategory(category) !in disabled

    fun isContinueCategory(category: String): Boolean = normalizedCategory(category) == homeContinueCategory

    /** iOS: `isLocalOnlyHomeShelfCategory` — nur lokal gebaut, nicht in `/personalized`. */
    fun isLocalOnlyCategory(category: String): Boolean =
        category == continueEbooksCategory || category == newestEpisodesCategory

    /**
     * iOS: `effectiveStartSettingsCategoryOrder` — Continue listening zuerst, dann Nutzer-Reihenfolge,
     * „New episodes“ nur mit Primary-Podcast-Bibliothek, „Continue reading“ immer verfügbar.
     */
    fun effectiveCategoryOrder(savedOrder: List<String>, showNewestEpisodes: Boolean): List<String> {
        val available = AbsStartShelfLocalization.settingsCategoryOrder.toMutableList()
        if (continueEbooksCategory !in available) {
            val idx = available.indexOf(homeContinueCategory)
            if (idx >= 0) available.add(idx + 1, continueEbooksCategory) else available.add(0, continueEbooksCategory)
        }
        if (showNewestEpisodes) {
            if (newestEpisodesCategory !in available) {
                val ebookIdx = available.indexOf(continueEbooksCategory)
                val contIdx = available.indexOf(homeContinueCategory)
                when {
                    ebookIdx >= 0 -> available.add(ebookIdx + 1, newestEpisodesCategory)
                    contIdx >= 0 -> available.add(contIdx + 1, newestEpisodesCategory)
                    else -> available.add(newestEpisodesCategory)
                }
            }
        } else {
            available.removeAll { it == newestEpisodesCategory }
        }
        val savedTail = savedOrder.filter { it != homeContinueCategory && it in available }
        val remaining = available.filter { it != homeContinueCategory }.toMutableList()
        val result = mutableListOf(homeContinueCategory)
        for (id in savedTail) {
            if (id !in remaining) continue
            result.add(id)
            remaining.remove(id)
        }
        result.addAll(remaining)
        return result
    }

    /** iOS: `updateStartSettingsCategoryList(parsed:)` — Labels aus Server-Regalen, sonst Standardtitel. */
    fun categoryList(order: List<String>, parsed: List<AbsStartShelfSection>): List<StartCategoryRow> {
        val fromServer = HashMap<String, String>()
        for (s in parsed) fromServer[s.category] = s.displayTitle
        return order.map { StartCategoryRow(it, AbsStartShelfLocalization.displayTitle(it, fromServer[it] ?: "")) }
    }

    /** iOS: `refreshStartSettingsCategoryListLabels` — bisherige Labels behalten. */
    fun categoryListKeepingLabels(order: List<String>, previous: List<StartCategoryRow>): List<StartCategoryRow> {
        val labels = previous.associate { it.category to it.label }
        return order.map { StartCategoryRow(it, labels[it] ?: AbsStartShelfLocalization.displayTitle(it, "")) }
    }

    /** iOS: `applyStartCategoryOrderKeepingContinueFirst`. */
    fun orderKeepingContinueFirst(order: List<String>): List<String> =
        listOf(homeContinueCategory) + order.filter { it != homeContinueCategory }

    /**
     * iOS: `moveStartSettingsCategory(dragging:onto:)` — `from` an die Stelle von `onto`; Continue
     * listening bleibt fix. `null` = keine Änderung.
     */
    fun moveCategory(categories: List<String>, fromId: String, ontoId: String): List<String>? {
        if (fromId == homeContinueCategory || ontoId == homeContinueCategory) return null
        val from = categories.indexOf(fromId)
        val to = categories.indexOf(ontoId)
        if (from < 0 || to < 0 || from == to) return null
        val next = categories.toMutableList()
        val item = next.removeAt(from)
        next.add(to, item)
        return orderKeepingContinueFirst(next)
    }

    /**
     * iOS: `startShelves(forHomeBrowseSection:)` — `continue` = alle eingeschalteten Regale in
     * Settings-Reihenfolge; Legacy-„recent“ = Newest-Regale; sonst das eine Regal.
     */
    fun shelvesForHomeBrowseSection(
        sectionId: String,
        categoryList: List<StartCategoryRow>,
        shelves: List<AbsStartShelfSection>,
        disabled: Set<String>,
    ): List<AbsStartShelfSection> {
        fun shelf(cat: String) = shelves.firstOrNull { it.category == cat }
        return when (sectionId) {
            AbsStartShelfLocalization.homeBrowseContinueSectionID ->
                categoryList.mapNotNull { row -> if (isEnabled(row.category, disabled)) shelf(row.category) else null }
            AbsStartShelfLocalization.homeBrowseRecentSectionID ->
                AbsStartShelfLocalization.homeBrowseRecentCategories.mapNotNull { if (isEnabled(it, disabled)) shelf(it) else null }
            else -> listOfNotNull(shelf(sectionId))
        }
    }

    /** iOS: `isAnyHomeBrowseContinueShelfEnabled`. */
    fun isAnyShelfEnabled(categoryList: List<StartCategoryRow>, disabled: Set<String>): Boolean =
        categoryList.any { isEnabled(it.category, disabled) }

    /** iOS: `homeBrowseStripRows` — nur „Dashboard“ (offline immer, online wenn ein Regal an ist). */
    fun homeBrowseStripIds(offline: Boolean, anyEnabled: Boolean): List<String> =
        if (offline || anyEnabled) listOf(AbsStartShelfLocalization.homeBrowseContinueSectionID) else emptyList()

    /** iOS: `clampHomeBrowseSectionIfNeeded` — frühere Einzel-Pills fallen auf Dashboard zurück. */
    fun clampHomeBrowseCategory(current: String, categoryList: List<StartCategoryRow>, stripIds: List<String>): String {
        val continueId = AbsStartShelfLocalization.homeBrowseContinueSectionID
        var value = current
        val mapsIntoContinue = AbsStartShelfLocalization.isHomeBrowseContinueCategory(value) ||
            AbsStartShelfLocalization.isHomeBrowseRecentCategory(value) ||
            AbsStartShelfLocalization.isHomeBrowseStatsCategory(value) ||
            value == AbsStartShelfLocalization.homeBrowseRecentSectionID ||
            categoryList.any { it.category == value }
        if (mapsIntoContinue) value = continueId
        if (stripIds.isEmpty() || value in stripIds) return value
        return if (continueId in stripIds) continueId else stripIds[0]
    }

    /** iOS: Initialwert von `homeBrowseCategory` aus den Prefs. */
    fun initialHomeBrowseCategory(saved: String?): String {
        val s = saved.orEmpty()
        if (AbsStartShelfLocalization.isHomeBrowseContinueCategory(s)) return AbsStartShelfLocalization.homeBrowseContinueSectionID
        if (AbsStartShelfLocalization.isHomeBrowseRecentCategory(s)) return AbsStartShelfLocalization.homeBrowseRecentSectionID
        return s.ifEmpty { AbsStartShelfLocalization.homeBrowseContinueSectionID }
    }

    // MARK: - Regale zusammenführen

    /** iOS: `preferredContinueListeningBook` — mehr Spuren, dann längerer Titel. */
    private fun preferredContinueBook(a: AbsBook, b: AbsBook): AbsBook {
        val ta = a.media.numTracks ?: 0
        val tb = b.media.numTracks ?: 0
        if (ta != tb) return if (ta > tb) a else b
        if (a.displayTitle.length != b.displayTitle.length) return if (a.displayTitle.length >= b.displayTitle.length) a else b
        return a
    }

    /** iOS: `dedupeContinueListeningBooks` — eine Zeile je ID, nach `lastUpdate` absteigend (stabil). */
    fun dedupeContinueBooks(books: List<AbsBook>, progress: Map<String, AbsUserMediaProgress>): List<AbsBook> {
        val byId = LinkedHashMap<String, AbsBook>()
        for (b in books) byId[b.id] = byId[b.id]?.let { preferredContinueBook(it, b) } ?: b
        return byId.values.sortedByDescending { progress[it.id]?.lastUpdate ?: 0 }
    }

    /** iOS: `dedupePodcastEpisodesForHomeContinueList`. */
    fun dedupeContinueEpisodes(
        episodes: List<AbsPodcastEpisodeListItem>,
        progress: Map<String, AbsUserMediaProgress>,
    ): List<AbsPodcastEpisodeListItem> =
        AbsPodcastEpisodeListItem.dedupeRows(episodes.sortedByDescending { progress[it.progressLookupKey]?.lastUpdate ?: 0 })

    /**
     * iOS: `mergedShelfBooks` — Continue nach „zuletzt gehört“, „Recently added“ nach `addedAt`
     * (stabil; ohne Datum hinter den datierten), sonst Server-Reihenfolge ohne Dubletten.
     */
    fun mergedShelfBooks(books: List<AbsBook>, category: String, progress: Map<String, AbsUserMediaProgress>): List<AbsBook> {
        if (category == homeContinueCategory || category == legacyFallbackCategory) return dedupeContinueBooks(books, progress)
        val seen = HashSet<String>()
        val out = books.filter { seen.add(it.id) }
        if (category != "newestItems") return out
        return out.withIndex().sortedWith { l, r ->
            val la = l.value.addedAt
            val ra = r.value.addedAt
            when {
                la != null && ra != null && la != ra -> ra.compareTo(la)
                la != null && ra == null -> -1
                la == null && ra != null -> 1
                else -> l.index.compareTo(r.index)
            }
        }.map { it.value }
    }

    /** iOS: `mergePersonalizedStartShelves` — Regale mehrerer Books-Bibliotheken je Kategorie vereinen. */
    fun mergePersonalizedShelves(
        base: List<AbsStartShelfSection>,
        extra: List<AbsStartShelfSection>,
        progress: Map<String, AbsUserMediaProgress>,
    ): List<AbsStartShelfSection> {
        if (base.isEmpty()) return extra
        if (extra.isEmpty()) return base
        val byCategory = LinkedHashMap<String, AbsStartShelfSection>()
        for (shelf in base + extra) {
            val existing = byCategory[shelf.category]
            if (existing == null) {
                byCategory[shelf.category] = shelf
                continue
            }
            val authors = LinkedHashMap<String, AbsAuthorShelfEntity>()
            (existing.authors + shelf.authors).forEach { authors[it.id] = it }
            val series = LinkedHashMap<String, AbsLibrarySeriesListItem>()
            (existing.series + shelf.series).forEach { series[it.id] = it }
            byCategory[shelf.category] = existing.copy(
                displayTitle = existing.displayTitle.ifEmpty { shelf.displayTitle },
                books = mergedShelfBooks(existing.books + shelf.books, shelf.category, progress),
                podcastEpisodes = dedupeContinueEpisodes(existing.podcastEpisodes + shelf.podcastEpisodes, progress),
                authors = authors.values.toList(),
                series = series.values.toList(),
            )
        }
        return byCategory.values.toList()
    }

    /** iOS: `recomputeStartBooksUnion` — alle Bücher der Regale (inkl. Serien-Bücher), ohne Dubletten. */
    fun startBooksUnion(shelves: List<AbsStartShelfSection>): List<AbsBook> {
        val seen = HashSet<String>()
        val out = ArrayList<AbsBook>()
        for (s in shelves) {
            s.books.forEach { if (seen.add(it.id)) out.add(it) }
            s.series.forEach { ser -> ser.books.orEmpty().forEach { if (seen.add(it.id)) out.add(it) } }
        }
        return out
    }

    /** iOS: `startShelvesHaveSameLayout`. */
    fun haveSameLayout(lhs: List<AbsStartShelfSection>, rhs: List<AbsStartShelfSection>): Boolean =
        lhs.size == rhs.size && lhs.zip(rhs).all { (a, b) -> a.category == b.category && a.id == b.id }

    /** iOS: `upsertLocalOnlyHomeShelf` — an der Settings-Position einfügen (Fallback: nach Continue). */
    fun upsertLocalOnlyShelf(
        section: AbsStartShelfSection,
        shelves: List<AbsStartShelfSection>,
        order: List<String>,
    ): List<AbsStartShelfSection> {
        val result = shelves.filter { it.category != section.category }.toMutableList()
        val want = order.indexOf(section.category)
        if (want >= 0) {
            val insertAt = result.indexOfFirst { existing ->
                val o = order.indexOf(existing.category)
                o >= 0 && o > want
            }.let { if (it < 0) result.size else it }
            result.add(insertAt, section)
            return result
        }
        val cont = result.indexOfFirst { isContinueCategory(it.category) }
        if (cont >= 0) result.add(cont + 1, section) else result.add(0, section)
        return result
    }

    /** iOS: `mergingPreservedLocalOnlyHomeShelves` — Server-Layout, lokal-only Regale aus [prior] behalten. */
    fun mergingPreservedLocalOnly(
        next: List<AbsStartShelfSection>,
        prior: List<AbsStartShelfSection>,
        disabled: Set<String>,
        order: List<String>,
    ): List<AbsStartShelfSection> {
        var result = next.filter { !isLocalOnlyCategory(it.category) }
        prior.filter { isLocalOnlyCategory(it.category) && isEnabled(it.category, disabled) }
            .forEach { result = upsertLocalOnlyShelf(it, result, order) }
        return result
    }

    // MARK: - Continue listening

    /** iOS: `qualifiesForContinueListeningShelf(bookId:)` / `(episodeKey:)`. */
    fun qualifiesForContinue(key: String, ctx: ContinueContext): Boolean {
        val k = key.swiftTrim()
        if (k.isNotEmpty() && k in ctx.blockedKeys) return false
        if (ctx.activeKey != null && ctx.activeKey == k) return true
        val p = ctx.progress[k] ?: return false
        if (p.isFinished) return false
        return p.currentTime > continueListeningMinPositionSeconds
    }

    /** iOS: `preferredHomeContinueShelfIndex`. */
    fun preferredContinueShelfIndex(shelves: List<AbsStartShelfSection>, disabled: Set<String>): Int =
        shelves.indexOfFirst { isContinueCategory(it.category) && isEnabled(it.category, disabled) }

    /** iOS: `makeContinueListeningShelf`. */
    fun makeContinueShelf(
        id: String,
        books: List<AbsBook>,
        episodes: List<AbsPodcastEpisodeListItem>,
        displayTitle: String? = null,
    ) = AbsStartShelfSection(
        id = id,
        category = homeContinueCategory,
        displayTitle = displayTitle ?: AbsStartShelfLocalization.displayTitle(homeContinueCategory, ""),
        books = books,
        podcastEpisodes = episodes,
    )

    /**
     * Gemeinsamer Kern von iOS `mergeServerAudiobooksIntoContinueShelves`, `mergeServerPodcastEpisodes…`,
     * `preserveValidContinueListeningItems`, `repairContinueListeningShelfFromLocalProgressOnly`:
     * fehlende Einträge ins Continue-Regal ergänzen bzw. ein neues Regal mit [newShelfId] vorn
     * einfügen. Gibt `null` zurück, wenn sich nichts ändert.
     */
    fun mergeIntoContinueShelf(
        shelves: List<AbsStartShelfSection>,
        books: List<AbsBook>,
        episodes: List<AbsPodcastEpisodeListItem>,
        disabled: Set<String>,
        progress: Map<String, AbsUserMediaProgress>,
        newShelfId: String,
        forceCanonicalCategory: Boolean = false,
    ): List<AbsStartShelfSection>? {
        if (books.isEmpty() && episodes.isEmpty()) return null
        val idx = preferredContinueShelfIndex(shelves, disabled)
        if (idx < 0) {
            val section = makeContinueShelf(newShelfId, dedupeContinueBooks(books, progress), dedupeContinueEpisodes(episodes, progress))
            return listOf(section) + shelves
        }
        val shelf = shelves[idx]
        val bookIds = shelf.books.mapTo(HashSet()) { it.id }
        val epKeys = shelf.podcastEpisodes.mapTo(HashSet()) { it.canonicalDedupeKey }
        val booksToAdd = books.filter { it.id !in bookIds }
        val epsToAdd = episodes.filter { it.canonicalDedupeKey !in epKeys }
        val categoryChanged = forceCanonicalCategory && shelf.category != homeContinueCategory
        if (booksToAdd.isEmpty() && epsToAdd.isEmpty() && !categoryChanged) return null
        val mergedBooks = if (booksToAdd.isEmpty()) shelf.books else dedupeContinueBooks(shelf.books + booksToAdd, progress)
        val mergedEps = if (epsToAdd.isEmpty()) shelf.podcastEpisodes else dedupeContinueEpisodes(shelf.podcastEpisodes + epsToAdd, progress)
        val replaced = if (forceCanonicalCategory) {
            makeContinueShelf(shelf.id, mergedBooks, mergedEps, shelf.displayTitle)
        } else {
            shelf.copy(books = mergedBooks, podcastEpisodes = mergedEps)
        }
        return shelves.toMutableList().also { it[idx] = replaced }
    }

    /**
     * iOS: `applyContinueListeningFinishedFilter` — fertige/zu kurze/blockierte Einträge aus Continue
     * entfernen und nach `lastUpdate` sortieren. `null` = unverändert.
     */
    fun applyFinishedFilter(shelves: List<AbsStartShelfSection>, ctx: ContinueContext): List<AbsStartShelfSection>? {
        if (shelves.isEmpty()) return null
        var changed = false
        val next = shelves.map { shelf ->
            if (!isContinueCategory(shelf.category)) return@map shelf
            val books = dedupeContinueBooks(shelf.books.filter { qualifiesForContinue(it.id, ctx) }, ctx.progress)
            val eps = dedupeContinueEpisodes(shelf.podcastEpisodes.filter { qualifiesForContinue(it.progressLookupKey, ctx) }, ctx.progress)
            if (books.map { it.id } == shelf.books.map { it.id } &&
                eps.map { it.progressLookupKey } == shelf.podcastEpisodes.map { it.progressLookupKey }
            ) return@map shelf
            changed = true
            shelf.copy(books = books, podcastEpisodes = eps)
        }
        return if (changed) next else null
    }

    /**
     * iOS: `normalizeHomeContinueListeningShelves` + `consolidateHomeContinueListeningShelves` —
     * Legacy-Kategorie umbenennen, mehrere Continue-Regale zu einem zusammenführen. `null` = unverändert.
     */
    fun normalizeContinueShelves(
        shelves: List<AbsStartShelfSection>,
        disabled: Set<String>,
        progress: Map<String, AbsUserMediaProgress>,
    ): List<AbsStartShelfSection>? {
        var current = shelves
        var changed = false
        if (current.any { it.category == legacyFallbackCategory }) {
            current = current.map {
                if (it.category == legacyFallbackCategory) makeContinueShelf(it.id, it.books, it.podcastEpisodes, it.displayTitle) else it
            }
            changed = true
        }
        val slots = current.withIndex().filter { isContinueCategory(it.value.category) && isEnabled(it.value.category, disabled) }
        if (slots.isEmpty()) return if (changed) current else null
        if (slots.size == 1) {
            val only = slots[0]
            val books = dedupeContinueBooks(only.value.books, progress)
            val eps = dedupeContinueEpisodes(only.value.podcastEpisodes, progress)
            if (books.map { it.id } == only.value.books.map { it.id } &&
                eps.map { it.progressLookupKey } == only.value.podcastEpisodes.map { it.progressLookupKey }
            ) return if (changed) current else null
            return current.toMutableList().also { it[only.index] = only.value.copy(books = books, podcastEpisodes = eps) }
        }
        val preferred = slots[0]
        val merged = makeContinueShelf(
            preferred.value.id,
            dedupeContinueBooks(slots.flatMap { it.value.books }, progress),
            dedupeContinueEpisodes(slots.flatMap { it.value.podcastEpisodes }, progress),
            preferred.value.displayTitle,
        )
        val remove = slots.map { it.index }.filter { it != preferred.index }.toSet()
        return current.withIndex().filter { it.index !in remove }.map { if (it.index == preferred.index) merged else it.value }
    }

    /** iOS: `inProgressAudiobookCandidates(from:)`. */
    fun inProgressAudiobookCandidates(
        payload: AbsItemsInProgressPayload,
        ctx: ContinueContext,
        activeBookLibraryIds: Set<String>,
        selectedBooksLibraryId: String?,
    ): List<AbsBook> {
        if (activeBookLibraryIds.isEmpty() && selectedBooksLibraryId == null) return emptyList()
        return payload.books.filter { book ->
            val lid = book.libraryId ?: return@filter true
            if (activeBookLibraryIds.isNotEmpty()) lid in activeBookLibraryIds else lid == selectedBooksLibraryId
        }.filter { it.isPlayableAudiobook }
            .filter { book ->
                if (book.id in ctx.blockedKeys) return@filter false
                val p = ctx.progress[book.id] ?: return@filter false
                !p.isFinished && p.currentTime > continueListeningMinPositionSeconds
            }
            .sortedByDescending { ctx.lastUpdate(it.id) }
    }

    /** iOS: `inProgressPodcastEpisodeCandidates(from:)`. */
    fun inProgressPodcastEpisodeCandidates(
        payload: AbsItemsInProgressPayload,
        ctx: ContinueContext,
        activePodcastLibraryIds: Set<String>,
        resolvedPodcastLibraryId: String?,
    ): List<AbsPodcastEpisodeListItem> {
        if (activePodcastLibraryIds.isEmpty() && resolvedPodcastLibraryId == null) return emptyList()
        val eps = payload.podcastEpisodes.filter { ep ->
            val lid = ep.libraryId ?: return@filter true
            if (activePodcastLibraryIds.isNotEmpty()) lid in activePodcastLibraryIds else lid == resolvedPodcastLibraryId
        }.filter { ep ->
            val key = ep.progressLookupKey
            if (key in ctx.blockedKeys) return@filter false
            val p = ctx.progress[key] ?: return@filter false
            !p.isFinished
        }.sortedByDescending { ctx.lastUpdate(it.progressLookupKey) }
        return dedupeContinueEpisodes(eps, ctx.progress)
    }

    /**
     * iOS: `localContinueAudiobookBookCandidates` — Hörbücher aus Katalog/Start-Union/Downloads mit
     * offenem lokalem Fortschritt. Bibliothekswahl grenzt nur ein; Downloads zählen immer.
     */
    fun localContinueAudiobookCandidates(
        pool: List<AbsBook>,
        downloadedIds: Set<String>,
        ctx: ContinueContext,
        activeBookLibraryIds: Set<String>,
        selectedBooksLibraryId: String?,
    ): List<AbsBook> {
        if (activeBookLibraryIds.isEmpty() && selectedBooksLibraryId == null && downloadedIds.isEmpty()) return emptyList()
        val seen = HashSet<String>()
        val out = ArrayList<AbsBook>()
        for (b in pool) {
            if (!seen.add(b.id)) continue
            if (!b.isPlayableAudiobook) continue
            if (b.id !in downloadedIds) {
                val lid = b.libraryId?.swiftTrim().orEmpty()
                if (lid.isNotEmpty()) {
                    if (activeBookLibraryIds.isNotEmpty()) {
                        if (lid !in activeBookLibraryIds) continue
                    } else if (!selectedBooksLibraryId.isNullOrEmpty() && lid != selectedBooksLibraryId) {
                        continue
                    }
                }
            }
            val p = ctx.progress[b.id] ?: continue
            if (p.isFinished || p.currentTime <= continueListeningMinPositionSeconds) continue
            if (p.episodeId?.swiftTrim().orEmpty().isNotEmpty()) continue
            out.add(b)
        }
        return out.sortedByDescending { ctx.lastUpdate(it.id) }
    }

    /** iOS: `localContinuePodcastEpisodeCandidates`. */
    fun localContinueEpisodeCandidates(
        pool: List<AbsPodcastEpisodeListItem>,
        ctx: ContinueContext,
        activePodcastLibraryIds: Set<String>,
        resolvedPodcastLibraryId: String?,
    ): List<AbsPodcastEpisodeListItem> {
        var rows = pool.filter { e ->
            val p = ctx.progress[e.progressLookupKey] ?: return@filter false
            !p.isFinished && p.currentTime > continueListeningMinPositionSeconds
        }
        if (resolvedPodcastLibraryId != null) {
            rows = rows.filter { row ->
                val lid = row.libraryId?.swiftTrim()?.ifEmpty { null } ?: return@filter true
                if (activePodcastLibraryIds.isNotEmpty()) lid in activePodcastLibraryIds else lid == resolvedPodcastLibraryId
            }
        }
        return dedupeContinueEpisodes(rows, ctx.progress)
    }

    /** Continue-Regal hat sichtbare Einträge (Bootstrap-Prüfung `continueShelfHasVisibleItems`). */
    fun continueShelfHasVisibleItems(shelves: List<AbsStartShelfSection>, disabled: Set<String>): Boolean {
        val idx = preferredContinueShelfIndex(shelves, disabled)
        return idx >= 0 && (shelves[idx].hasBooks || shelves[idx].hasPodcastEpisodes)
    }

    /** iOS: `hasOpenProgressExpectingContinue` — offener Hörfortschritt, der ins Regal gehört. */
    fun hasOpenProgressExpectingContinue(progress: Map<String, AbsUserMediaProgress>): Boolean =
        progress.values.any { !it.isFinished && it.currentTime > continueListeningMinPositionSeconds }

    /** iOS: `startDashboardShelfHasVisibleContent`. */
    fun shelfHasVisibleContent(shelf: AbsStartShelfSection): Boolean =
        shelf.hasBooks || shelf.hasPodcastEpisodes || shelf.hasSeries || shelf.hasAuthors

    /** iOS: `newestEpisodes`-Fallback `localNewestEpisodeCandidates` — neueste zuerst, max. [limit]. */
    fun newestEpisodeCandidates(pool: List<AbsPodcastEpisodeListItem>, libraryId: String, limit: Int = 14): List<AbsPodcastEpisodeListItem> {
        val lib = libraryId.swiftTrim()
        val rows = pool.filter { ep -> ep.libraryId?.swiftTrim()?.ifEmpty { null }?.let { it == lib } ?: true }
        return AbsPodcastEpisodeListItem.dedupeRows(rows).sortedByDescending { it.publishedAt ?: 0 }.take(limit)
    }

    /**
     * iOS: `mergedUserMediaProgress(existing:incoming:)` (vereinfacht) — neuere `lastUpdate` gewinnt;
     * bei Gleichstand die eingehende Zeile.
     */
    fun mergedProgress(existing: AbsUserMediaProgress?, incoming: AbsUserMediaProgress): AbsUserMediaProgress {
        if (existing == null) return incoming
        val e = existing.lastUpdate ?: 0
        val i = incoming.lastUpdate ?: 0
        return if (e > i) existing else incoming
    }

    /** iOS: `ebookDisplayProgressFraction` — Max aus Server-`ebookProgress` und lokaler Readium-Fraktion; ≥ 99,5 % = 1. */
    fun ebookDisplayFraction(server: Double?, local: Double?): Double? {
        val f = listOfNotNull(server, local).maxOrNull() ?: return null
        if (f <= 0.005) return null
        val clamped = f.coerceIn(0.0, 1.0)
        return if (clamped >= 0.995) 1.0 else clamped
    }
}
