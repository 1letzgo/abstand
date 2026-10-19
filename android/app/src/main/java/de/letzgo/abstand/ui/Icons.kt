package de.letzgo.abstand.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.VolumeDown
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.automirrored.outlined.ManageSearch
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * SF Symbol → Material-Icon. Namen = SF-Name in lowerCamelCase (`house.fill` → [SF.houseFill]),
 * damit Ports die iOS-Symbole 1:1 wiederfinden. Enthält jedes `systemImage:`/`Image(systemName:)`
 * aus den iOS-Quellen (`abstand/`). Dynamische Symbolnamen (z. B. aus Shelf-Kategorien) über [SF.named].
 * Neue Symbole hier ergänzen statt pro Screen ad hoc Icons zu wählen.
 */
object SF {
    val arrowClockwise = Icons.Filled.Refresh
    val arrowClockwiseCircle = Icons.Outlined.Refresh
    val arrowCounterclockwise = Icons.Filled.Replay
    val arrowCounterclockwiseCircleFill = Icons.Filled.Restore
    val arrowDown = Icons.Filled.ArrowDownward
    val arrowDownCircle = Icons.Outlined.ArrowCircleDown
    val arrowDownCircleFill = Icons.Filled.ArrowCircleDown
    val arrowDownCircleBadgeXmark = Icons.Outlined.FileDownloadOff
    val arrowRight = Icons.AutoMirrored.Filled.ArrowForward
    val arrowTriangle2Circlepath = Icons.Filled.Sync
    val arrowUp = Icons.Filled.ArrowUpward
    val arrowUpArrowDown = Icons.Filled.SwapVert
    val arrowUturnBackward = Icons.AutoMirrored.Filled.Undo
    val backwardEnd = Icons.Filled.SkipPrevious
    val forwardEnd = Icons.Filled.SkipNext
    val boltFill = Icons.Filled.Bolt
    val book = Icons.AutoMirrored.Outlined.MenuBook
    val bookFill = Icons.AutoMirrored.Filled.MenuBook
    val bookClosed = Icons.Outlined.Book
    val bookClosedFill = Icons.Filled.Book
    val bookPages = Icons.Outlined.AutoStories
    val bookmark = Icons.Outlined.BookmarkBorder
    val bookmarkFill = Icons.Filled.Bookmark
    val booksVertical = Icons.AutoMirrored.Outlined.LibraryBooks
    val booksVerticalFill = Icons.AutoMirrored.Filled.LibraryBooks
    val building2Fill = Icons.Filled.Business
    val calendar = Icons.Outlined.CalendarToday
    val calendarBadgeClock = Icons.Outlined.EventAvailable
    val captionsBubble = Icons.Outlined.ClosedCaption
    val characterBookClosed = Icons.Outlined.Spellcheck
    val chartBar = Icons.Outlined.BarChart
    val chartBarFill = Icons.Filled.BarChart
    val checkmark = Icons.Filled.Check
    val checkmarkCircle = Icons.Outlined.CheckCircle
    val checkmarkCircleFill = Icons.Filled.CheckCircle
    val chevronDown = Icons.Filled.KeyboardArrowDown
    val chevronLeft = Icons.AutoMirrored.Filled.KeyboardArrowLeft
    val chevronRight = Icons.AutoMirrored.Filled.KeyboardArrowRight
    val chevronUpChevronDown = Icons.Filled.UnfoldMore
    val circle = Icons.Outlined.Circle
    val circleDashed = Icons.Outlined.RadioButtonUnchecked
    val circleLefthalfFilled = Icons.Outlined.Contrast
    val clock = Icons.Outlined.Schedule
    val clockFill = Icons.Filled.Schedule
    val clockArrowCirclepath = Icons.Filled.History
    val docText = Icons.Outlined.Description
    val docTextMagnifyingglass = Icons.Outlined.FindInPage
    val dotRadiowavesLeftAndRight = Icons.Filled.Podcasts
    val dotRadiowavesUpForward = Icons.Filled.RssFeed
    /** iOS-„⋯“-Menü → Android-Überlaufmenü „⋮“. */
    val ellipsisCircle = Icons.Filled.MoreVert
    val exclamationmarkTriangle = Icons.Outlined.Warning
    val flameFill = Icons.Filled.LocalFireDepartment
    val folder = Icons.Outlined.Folder
    val folderFill = Icons.Filled.Folder
    val gearshape2 = Icons.Outlined.SettingsApplications
    val gearshapeFill = Icons.Filled.Settings
    /** Kontur-Variante für Kopfzeilen-Aktionen (wie Filter/Sortieren). */
    val gearshape = Icons.Outlined.Settings
    /** App-Version (Settings › Debug › App). */
    val infoCircle = Icons.Outlined.Info
    val globe = Icons.Outlined.Language
    val handTap = Icons.Outlined.TouchApp
    val headphones = Icons.Outlined.Headphones
    val headphonesCircleFill = Icons.Filled.Headphones
    val hourglass = Icons.Outlined.HourglassEmpty
    val houseFill = Icons.Filled.Home
    val icloud = Icons.Outlined.Cloud
    val icloudSlash = Icons.Outlined.CloudOff
    val internaldrive = Icons.Outlined.Storage
    val ladybug = Icons.Outlined.BugReport
    val lightbulbFill = Icons.Filled.Lightbulb
    val line3Horizontal = Icons.Filled.Menu
    val line3HorizontalDecreaseCircle = Icons.Outlined.FilterAlt
    val line3HorizontalDecreaseCircleFill = Icons.Filled.FilterAlt
    val link = Icons.Filled.Link
    val listBullet = Icons.AutoMirrored.Filled.List
    val listBulletBelowRectangle = Icons.AutoMirrored.Outlined.ListAlt
    val listStar = Icons.Outlined.Stars
    val lockFill = Icons.Filled.Lock
    val lockOpenFill = Icons.Filled.LockOpen
    val lockRotation = Icons.Filled.ScreenLockRotation
    val magnifyingglass = Icons.Filled.Search
    val mic = Icons.Outlined.Mic
    val micFill = Icons.Filled.Mic
    val minus = Icons.Filled.Remove
    val minusCircle = Icons.Outlined.RemoveCircleOutline
    val minusCircleFill = Icons.Filled.RemoveCircle
    val moon = Icons.Outlined.DarkMode
    val paintbrushFill = Icons.Filled.Brush
    val paintpaletteFill = Icons.Filled.Palette
    val pauseFill = Icons.Filled.Pause
    val pencil = Icons.Outlined.Edit
    val person2Fill = Icons.Filled.People
    val person2Slash = Icons.Outlined.PersonOff
    val personBadgeKeyFill = Icons.Filled.AdminPanelSettings
    val personCropCircle = Icons.Outlined.AccountCircle
    val personCropCircleFill = Icons.Filled.AccountCircle
    val personFill = Icons.Filled.Person
    val personTextRectangle = Icons.Outlined.Badge
    val personWave2 = Icons.Outlined.RecordVoiceOver
    val personWave2Fill = Icons.Filled.RecordVoiceOver
    val photo = Icons.Outlined.Image
    val photoOnRectangleAngled = Icons.Outlined.PhotoLibrary
    val play = Icons.Outlined.PlayArrow
    val playCircle = Icons.Outlined.PlayCircle
    val playCircleFill = Icons.Filled.PlayCircle
    val playFill = Icons.Filled.PlayArrow
    val plus = Icons.Filled.Add
    val plusCircle = Icons.Outlined.AddCircleOutline
    val plusCircleFill = Icons.Filled.AddCircle
    val plusRectangleOnRectangle = Icons.Outlined.LibraryAdd
    val rectanglePortraitAndArrowRight = Icons.AutoMirrored.Filled.Logout
    val rectangleStack = Icons.Outlined.CollectionsBookmark
    val rectangleStackFill = Icons.Filled.CollectionsBookmark
    val scroll = Icons.Outlined.HistoryEdu
    val serverRack = Icons.Outlined.Dns
    val sliderHorizontal3 = Icons.Filled.Tune
    val sparkles = Icons.Filled.AutoAwesome
    val speakerWave1 = Icons.AutoMirrored.Filled.VolumeDown
    val speakerWave3 = Icons.AutoMirrored.Filled.VolumeUp
    val squareAndArrowUp = Icons.Filled.Share
    val squareGrid2x2 = Icons.Outlined.GridView
    val squareGrid2x2Fill = Icons.Filled.GridView
    val sunMax = Icons.Outlined.LightMode
    val sunMaxFill = Icons.Filled.LightMode
    val tag = Icons.Outlined.Sell
    val tagFill = Icons.Filled.Sell
    val textAlignleft = Icons.AutoMirrored.Filled.Notes
    val textBookClosed = Icons.Outlined.ImportContacts
    val textBubble = Icons.Outlined.ChatBubbleOutline
    val textMagnifyingglass = Icons.AutoMirrored.Outlined.ManageSearch
    val textPage = Icons.AutoMirrored.Outlined.Article
    val textQuote = Icons.Filled.FormatQuote
    val textWordSpacing = Icons.Outlined.SpaceBar
    val textformatSizeLarger = Icons.Filled.TextIncrease
    val textformatSizeSmaller = Icons.Filled.TextDecrease
    val translate = Icons.Filled.Translate
    val trash = Icons.Outlined.Delete
    val trayFull = Icons.Outlined.Inbox
    val waveform = Icons.Filled.GraphicEq
    val xmark = Icons.Filled.Close
    val xmarkCircle = Icons.Outlined.Cancel
    val xmarkCircleFill = Icons.Filled.Cancel

    /** iOS: `gobackward.<n>` (PlaybackController.gobackwardSystemImage) — 5/10/30 haben eigene Material-Icons. */
    fun gobackward(seconds: Int): ImageVector = when (seconds) {
        5 -> Icons.Filled.Replay5
        10 -> Icons.Filled.Replay10
        30 -> Icons.Filled.Replay30
        else -> Icons.Filled.Replay
    }

    /** iOS: `goforward.<n>`. */
    fun goforward(seconds: Int): ImageVector = when (seconds) {
        5 -> Icons.Filled.Forward5
        10 -> Icons.Filled.Forward10
        30 -> Icons.Filled.Forward30
        else -> Icons.Filled.FastForward
    }

    /** SF-Name → Icon für dynamische Symbolnamen (z. B. `ABSStartShelfLocalization.stripSystemImage`). */
    val byName: Map<String, ImageVector> by lazy {
        mapOf(
            "arrow.clockwise" to arrowClockwise, "arrow.clockwise.circle" to arrowClockwiseCircle,
            "arrow.counterclockwise" to arrowCounterclockwise,
            "arrow.counterclockwise.circle.fill" to arrowCounterclockwiseCircleFill,
            "arrow.down" to arrowDown, "arrow.down.circle" to arrowDownCircle,
            "arrow.down.circle.fill" to arrowDownCircleFill, "arrow.down.circle.badge.xmark" to arrowDownCircleBadgeXmark,
            "arrow.right" to arrowRight, "arrow.triangle.2.circlepath" to arrowTriangle2Circlepath,
            "arrow.up" to arrowUp, "arrow.up.arrow.down" to arrowUpArrowDown, "arrow.uturn.backward" to arrowUturnBackward,
            "backward.end" to backwardEnd, "forward.end" to forwardEnd, "bolt.fill" to boltFill,
            "book" to book, "book.fill" to bookFill, "book.closed" to bookClosed, "book.closed.fill" to bookClosedFill,
            "book.pages" to bookPages, "bookmark" to bookmark, "bookmark.fill" to bookmarkFill,
            "books.vertical" to booksVertical, "books.vertical.fill" to booksVerticalFill,
            "building.2.fill" to building2Fill, "calendar" to calendar, "calendar.badge.clock" to calendarBadgeClock,
            "captions.bubble" to captionsBubble, "character.book.closed" to characterBookClosed,
            "chart.bar" to chartBar, "chart.bar.fill" to chartBarFill, "checkmark" to checkmark,
            "checkmark.circle" to checkmarkCircle, "checkmark.circle.fill" to checkmarkCircleFill,
            "chevron.down" to chevronDown, "chevron.left" to chevronLeft, "chevron.right" to chevronRight,
            "chevron.up.chevron.down" to chevronUpChevronDown, "circle" to circle, "circle.dashed" to circleDashed,
            "circle.lefthalf.filled" to circleLefthalfFilled, "clock" to clock, "clock.fill" to clockFill,
            "clock.arrow.circlepath" to clockArrowCirclepath, "doc.text" to docText,
            "doc.text.magnifyingglass" to docTextMagnifyingglass,
            "dot.radiowaves.left.and.right" to dotRadiowavesLeftAndRight, "dot.radiowaves.up.forward" to dotRadiowavesUpForward,
            "ellipsis.circle" to ellipsisCircle, "exclamationmark.triangle" to exclamationmarkTriangle,
            "flame.fill" to flameFill, "folder" to folder, "folder.fill" to folderFill,
            "gearshape.2" to gearshape2, "gearshape.fill" to gearshapeFill, "globe" to globe, "hand.tap" to handTap,
            "headphones" to headphones, "headphones.circle.fill" to headphonesCircleFill, "hourglass" to hourglass,
            "house.fill" to houseFill, "icloud" to icloud, "icloud.slash" to icloudSlash,
            "internaldrive" to internaldrive, "ladybug" to ladybug, "lightbulb.fill" to lightbulbFill,
            "line.3.horizontal" to line3Horizontal, "line.3.horizontal.decrease.circle" to line3HorizontalDecreaseCircle,
            "line.3.horizontal.decrease.circle.fill" to line3HorizontalDecreaseCircleFill, "link" to link,
            "list.bullet" to listBullet, "list.bullet.below.rectangle" to listBulletBelowRectangle, "list.star" to listStar,
            "lock.fill" to lockFill, "lock.open.fill" to lockOpenFill, "lock.rotation" to lockRotation,
            "magnifyingglass" to magnifyingglass, "mic" to mic, "mic.fill" to micFill, "minus" to minus,
            "minus.circle" to minusCircle, "minus.circle.fill" to minusCircleFill, "moon" to moon,
            "paintbrush.fill" to paintbrushFill, "paintpalette.fill" to paintpaletteFill, "pause.fill" to pauseFill,
            "pencil" to pencil, "person.2.fill" to person2Fill, "person.2.slash" to person2Slash,
            "person.badge.key.fill" to personBadgeKeyFill, "person.crop.circle" to personCropCircle,
            "person.crop.circle.fill" to personCropCircleFill, "person.fill" to personFill,
            "person.text.rectangle" to personTextRectangle, "person.wave.2" to personWave2,
            "person.wave.2.fill" to personWave2Fill, "photo" to photo, "photo.on.rectangle.angled" to photoOnRectangleAngled,
            "play" to play, "play.circle" to playCircle, "play.circle.fill" to playCircleFill, "play.fill" to playFill,
            "plus" to plus, "plus.circle" to plusCircle, "plus.circle.fill" to plusCircleFill,
            "plus.rectangle.on.rectangle" to plusRectangleOnRectangle,
            "rectangle.portrait.and.arrow.right" to rectanglePortraitAndArrowRight,
            "rectangle.stack" to rectangleStack, "rectangle.stack.fill" to rectangleStackFill, "scroll" to scroll,
            "server.rack" to serverRack, "slider.horizontal.3" to sliderHorizontal3, "sparkles" to sparkles,
            "speaker.wave.1" to speakerWave1, "speaker.wave.3" to speakerWave3, "square.and.arrow.up" to squareAndArrowUp,
            "square.grid.2x2" to squareGrid2x2, "square.grid.2x2.fill" to squareGrid2x2Fill,
            "sun.max" to sunMax, "sun.max.fill" to sunMaxFill, "tag" to tag, "tag.fill" to tagFill,
            "text.alignleft" to textAlignleft, "text.book.closed" to textBookClosed, "text.bubble" to textBubble,
            "text.magnifyingglass" to textMagnifyingglass, "text.page" to textPage, "text.quote" to textQuote,
            "text.word.spacing" to textWordSpacing, "textformat.size.larger" to textformatSizeLarger,
            "textformat.size.smaller" to textformatSizeSmaller, "translate" to translate, "trash" to trash,
            "tray.full" to trayFull, "waveform" to waveform, "xmark" to xmark, "xmark.circle" to xmarkCircle,
            "xmark.circle.fill" to xmarkCircleFill,
        )
    }

    /** SF-Name → Icon; `gobackward.N`/`goforward.N` werden aufgelöst, Unbekanntes → `null`. */
    fun named(name: String): ImageVector? {
        byName[name]?.let { return it }
        name.removePrefix("gobackward.").takeIf { it != name }?.toIntOrNull()?.let { return gobackward(it) }
        name.removePrefix("goforward.").takeIf { it != name }?.toIntOrNull()?.let { return goforward(it) }
        return null
    }
}

/** iOS: `DetailMetaLabelIcon.systemImage(for:)` — Symbol vor Meta-Sektionsüberschriften. */
object DetailMetaLabelIcon {
    fun icon(title: String): ImageVector? = when (title.trim().lowercase()) {
        "author" -> SF.personFill
        "narrator", "narrators" -> SF.micFill
        "series" -> SF.booksVerticalFill
        "publisher" -> SF.building2Fill
        "duration", "total runtime" -> SF.clockFill
        "year", "first release" -> SF.calendar
        "genres" -> SF.squareGrid2x2Fill
        "tags" -> SF.tagFill
        "description", "about" -> SF.textAlignleft
        "show", "feed type" -> SF.dotRadiowavesLeftAndRight
        "host", "hosts" -> SF.personWave2Fill
        "subtitle" -> SF.textQuote
        "published" -> SF.calendarBadgeClock
        "categories" -> SF.folderFill
        "episode" -> SF.waveform
        "show notes" -> SF.docText
        "chapters", "episodes" -> SF.listBullet
        "bookmarks" -> SF.bookmarkFill
        "listening history" -> SF.clockArrowCirclepath
        "language" -> SF.globe
        "rss feed", "feed" -> SF.dotRadiowavesUpForward
        "links" -> SF.link
        else -> null
    }
}
