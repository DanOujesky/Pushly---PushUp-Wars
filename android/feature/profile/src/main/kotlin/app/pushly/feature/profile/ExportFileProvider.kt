package app.pushly.feature.profile

import androidx.core.content.FileProvider

/** Own subclass so it can live next to other FileProviders in the merged manifest. */
class ExportFileProvider : FileProvider()
