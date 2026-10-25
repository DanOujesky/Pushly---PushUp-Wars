package app.pushly.feature.shop

import android.app.Activity
import android.content.Context
import app.pushly.core.common.Monetization
import app.pushly.core.common.PLog
import app.pushly.core.designsystem.AdSlots
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import com.revenuecat.purchases.Package as RcPackage

/** One plan on the paywall (from the RevenueCat "current" offering). Same as iOS `PaywallPlan`. */
data class PaywallPlan(val id: String, val kind: Kind, val price: String, val trialDays: Int?, internal val pkg: RcPackage? = null) {
    enum class Kind { Annual, Monthly, Lifetime, Other }
}

/**
 * Pushly Pro + ads in one place (doc 13, D-073), same as iOS `Shop`. Pro = active RevenueCat entitlement `pro`
 * (instant, on this device) OR `profiles.is_pro` from the server (the webhook — authoritative for server perks).
 * The app creates one `Shop`, calls [install] at launch and [identify] once the profile is known.
 */
class Shop(private val context: Context, val config: ShopConfig, history: AdHistory) {
    data class State(
        val storePro: Boolean = false,
        val serverPro: Boolean = false,
        val plans: List<PaywallPlan> = emptyList(),
        val loadingPlans: Boolean = false,
        val busy: Boolean = false,
        /** Last result shown on the paywall (string resource id). */
        val message: Int? = null,
        /** Set to present the paywall: profile | remove_ads | ghost_limit | sound | frame | emblem. */
        val paywallReason: String? = null,
        /** Me, for the paywall hero and the frame picker previews. */
        val me: Me? = null,
    ) {
        val isPro: Boolean get() = storePro || serverPro
    }

    data class Me(val username: String, val avatarPreset: String?)

    val ads = AdsManager(context, config, history)

    /** Saves my frame on the server (`set_profile_frame`, D-074) — set by the app. */
    @Volatile var saveFrame: (suspend (String?) -> Unit)? = null

    fun setMe(me: Me?) = _state.update { it.copy(me = me) }

    /** Pick a Pro frame (null = none). Pro only; the server checks it too. */
    suspend fun setFrame(id: String?): Boolean {
        val save = saveFrame ?: return false
        if (id != null && !_state.value.isPro) return false
        _state.update { it.copy(busy = true) }
        return try {
            save(id)
            Monetization.setFrame(id)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Purchases) { "Frame not saved: ${e.message}" }
            false
        } finally {
            _state.update { it.copy(busy = false) }
        }
    }
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()
    private var userId: String? = null

    /** The activity on screen (purchases, consent and interstitials need one). Set by MainActivity. */
    @Volatile var activity: (() -> Activity?) = { null }

    /** Plugs the hooks in: paywall requests, the battle-results interstitial and banner slots. */
    fun install() {
        Monetization.showPaywall = { reason -> _state.update { it.copy(paywallReason = reason, message = null) } }
        Monetization.battleClosed = { ads.battleClosed(activity()) }
        AdSlots.provider = { placement -> BannerAdSlot(placement, this) }
    }

    fun closePaywall() = _state.update { it.copy(paywallReason = null) }

    val purchasesAvailable: Boolean get() = config.purchasesAvailable

    /** Signed-in user (Supabase id = RevenueCat app user id, so the webhook can match purchases) + server Pro flag. */
    suspend fun identify(userId: String?, serverPro: Boolean) {
        _state.update { it.copy(serverPro = serverPro) }
        publish()
        if (!config.purchasesAvailable || userId == null) return
        try {
            if (!Purchases.isConfigured) {
                Purchases.configure(PurchasesConfiguration.Builder(context, config.revenueCatKey).appUserID(userId).build())
                Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
            } else if (this.userId != userId) {
                Purchases.sharedInstance.awaitLogIn(userId)
            }
            this.userId = userId
            apply(Purchases.sharedInstance.awaitCustomerInfo())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Purchases) { "RevenueCat identify failed: ${e.message}" }
        }
    }

    private fun apply(info: CustomerInfo) {
        _state.update { it.copy(storePro = info.entitlements["pro"]?.isActive == true) }
        publish()
    }

    private fun publish() {
        Monetization.isPro = _state.value.isPro
    }

    suspend fun loadPlans() {
        if (!config.purchasesAvailable || !Purchases.isConfigured) return
        _state.update { it.copy(loadingPlans = true) }
        try {
            val offering = Purchases.sharedInstance.awaitOfferings().current
            val plans = offering?.availablePackages.orEmpty().map(::plan).sortedBy { it.kind.ordinal }
            _state.update { it.copy(plans = plans, loadingPlans = false) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PLog.warning(PLog.Category.Purchases) { "Offerings failed: ${e.message}" }
            _state.update { it.copy(loadingPlans = false, message = R.string.paywall_load_failed) }
        }
    }

    suspend fun purchase(plan: PaywallPlan): Boolean {
        val pkg = plan.pkg ?: return false
        val act = activity() ?: return false
        _state.update { it.copy(busy = true, message = null) }
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(act, pkg).build())
            apply(result.customerInfo)
            _state.update { it.copy(busy = false, message = if (it.isPro) R.string.paywall_welcome else null) }
            _state.value.isPro
        } catch (e: PurchasesTransactionException) {
            _state.update { it.copy(busy = false, message = if (e.userCancelled) null else R.string.paywall_failed) }
            false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(busy = false, message = R.string.paywall_failed) }
            false
        }
    }

    suspend fun restore() {
        if (!config.purchasesAvailable || !Purchases.isConfigured) return
        _state.update { it.copy(busy = true) }
        try {
            apply(Purchases.sharedInstance.awaitRestore())
            _state.update { it.copy(busy = false, message = if (it.isPro) R.string.paywall_restored else R.string.paywall_nothing_to_restore) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _state.update { it.copy(busy = false, message = R.string.paywall_restore_failed) }
        }
    }

    companion object {
        internal fun plan(p: RcPackage): PaywallPlan {
            val kind = when (p.packageType) {
                PackageType.MONTHLY -> PaywallPlan.Kind.Monthly
                PackageType.ANNUAL -> PaywallPlan.Kind.Annual
                PackageType.LIFETIME -> PaywallPlan.Kind.Lifetime
                else -> PaywallPlan.Kind.Other
            }
            val free = p.product.defaultOption?.freePhase?.billingPeriod
            return PaywallPlan(p.identifier, kind, p.product.price.formatted, free?.let(::days), p)
        }

        internal fun days(period: Period): Int? = when (period.unit) {
            Period.Unit.DAY -> period.value
            Period.Unit.WEEK -> period.value * 7
            Period.Unit.MONTH -> period.value * 30
            Period.Unit.YEAR -> period.value * 365
            Period.Unit.UNKNOWN -> null
        }
    }
}
