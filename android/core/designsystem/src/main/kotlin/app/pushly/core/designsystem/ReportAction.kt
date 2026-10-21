package app.pushly.core.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import app.pushly.core.designsystem.generated.ColorTokens
import app.pushly.core.designsystem.generated.TypographyTokens
import kotlinx.coroutines.launch

/** The server's `reports.reason` values with their labels. Same list as iOS `ReportButton`. */
val reportReasons = listOf(
    "cheating" to R.string.report_cheating,
    "harassment" to R.string.report_harassment,
    "inappropriate_video" to R.string.report_video,
    "inappropriate_name" to R.string.report_name,
    "spam" to R.string.report_spam,
    "other" to R.string.report_other,
)

/** "Report" text action with a reason picker and a thank-you note. Used on profiles and battle results. */
@Composable
fun ReportAction(label: String = stringResource(R.string.report), modifier: Modifier = Modifier, onReport: suspend (String) -> Boolean) {
    var open by remember { mutableStateOf(false) }
    TokenText(
        label,
        TypographyTokens.BodyS,
        color = ColorTokens.StateDanger.resolve(),
        modifier = modifier.heightIn(min = MinTouchTarget).clickable(role = Role.Button) { open = true }
            .wrapContentHeight(Alignment.CenterVertically),
    )
    ReportDialog(open, onDismiss = { open = false }, onReport = onReport)
}

/** The reason picker + result note on its own, for long-press reports (clan chat messages). */
@Composable
fun ReportDialog(open: Boolean, onDismiss: () -> Unit, onReport: suspend (String) -> Boolean) {
    var result by remember { mutableStateOf<Boolean?>(null) }
    val scope = rememberCoroutineScope()
    if (open) {
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.report_title)) },
            text = {
                Column {
                    reportReasons.forEach { (id, label) ->
                        TokenText(
                            stringResource(label),
                            TypographyTokens.Body,
                            modifier = Modifier.fillMaxWidth().heightIn(min = MinTouchTarget).clickable(role = Role.Button) {
                                onDismiss()
                                scope.launch { result = onReport(id) }
                            }.wrapContentHeight(Alignment.CenterVertically),
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.report_cancel)) } },
        )
    }
    result?.let { ok ->
        AlertDialog(
            containerColor = ColorTokens.BgElevated.resolve(),
            onDismissRequest = { result = null },
            title = { Text(stringResource(if (ok) R.string.report_thanks else R.string.report_failed)) },
            text = { Text(stringResource(if (ok) R.string.report_thanks_text else R.string.report_failed_text)) },
            confirmButton = { TextButton(onClick = { result = null }) { Text(stringResource(R.string.report_ok)) } },
        )
    }
}
