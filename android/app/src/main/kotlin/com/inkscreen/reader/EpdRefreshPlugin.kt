package com.inkscreen.reader

import android.app.Activity
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 墨水屏刷新控制器：只做一件事 —— 在正确时机触发全刷/局刷。
 *
 * 各厂商无统一公开 API，这里用「候选类 + 反射 + 逐个尝试」策略：
 *   - Boox/Onyx: com.onyx.android.sdk.device.EpdController / EpdDeviceManager /
 *                DeviceInfoSingleton.getDevice(ctx).resetScreen(ctx)
 *   - 海信 Hisense: com.hisense.epd.Epd / com.hisense.android.graphics.EPDManager
 *   - 墨案 Moaan(inkPalm)：系统多基于 Onyx 类内核，走 Boox 候选；失败则走通用兜底
 *   - 通用兜底：decorView.invalidate()（多数机型默认局刷模式已足够流畅）
 *
 * 若厂商提供正式 AAR SDK，直接在对应分支替换反射调用即可，
 * Flutter 侧协议（full/partial/setMode/isEink）保持不变。
 */
object EpdRefreshPlugin {

    private const val CHANNEL = "ebook_reader/epd"

    /** 已识别到的可用刷新入口（懒加载缓存） */
    private var resolvedEntry: RefreshEntry? = null
    private var resolved: Boolean = false

    interface RefreshEntry {
        fun full(activity: Activity)
        fun partial(activity: Activity)
        val vendor: String

        /** 探测当前设备是否可用此刷新入口（不实际触发刷新） */
        fun test(activity: Activity): Boolean
    }

    /** 反射探测：类存在且至少有一个目标方法 */
    private fun classExists(className: String, methods: List<String>): Boolean =
        try {
            val clazz = Class.forName(className)
            methods.any { name -> clazz.methods.any { it.name == name } }
        } catch (_: Throwable) {
            false
        }

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "full" -> {
                    run(call, activity, full = true)
                    result.success(null)
                }
                "partial" -> {
                    run(call, activity, full = false)
                    result.success(null)
                }
                "setMode" -> {
                    // quality | speed | balanced —— 预留给厂商 SDK 的模式参数
                    result.success(null)
                }
                "isEink" -> result.success(looksLikeEink())
                else -> result.notImplemented()
            }
        }
    }

    private fun looksLikeEink(): Boolean {
        val vendors = listOf("onyx", "boox", "hisense", "moaan", "inkpalm",
            "hanvon", "ireader", "bigme", "dasung", "onyxboo")
        val m = Build.MANUFACTURER.lowercase() + " " + Build.BRAND.lowercase() +
                " " + Build.DEVICE.lowercase()
        return vendors.any { m.contains(it) }
    }

    private fun run(call: io.flutter.plugin.common.MethodCall, activity: Activity, full: Boolean) {
        val entry = resolve(activity)
        try {
            if (entry != null) {
                if (full) entry.full(activity) else entry.partial(activity)
                return
            }
        } catch (_: Throwable) {
            // 反射调用失败 → 兜底
        }
        genericFallback(activity, full)
    }

    /** 逐候选解析可用的厂商刷新入口，成功后缓存 */
    private fun resolve(activity: Activity): RefreshEntry? {
        if (resolved) return resolvedEntry
        resolved = true
        for (candidate in candidates()) {
            try {
                if (candidate.test(activity)) {
                    resolvedEntry = candidate
                    return candidate
                }
            } catch (_: Throwable) {
                // 类不存在 / 方法签名不匹配 → 下一个
            }
        }
        return null
    }

    private fun candidates(): List<RefreshEntry> = listOf(
        // ---- Boox / Onyx ----
        object : RefreshEntry {
            override val vendor = "onyx.EpdController"
            override fun full(a: Activity) = invokeStatic(
                "com.onyx.android.sdk.device.EpdController", "requestEpdMode", a,
                altMethods = listOf("fullRefresh", "invalidateScreen", "resetScreen"))
            override fun partial(a: Activity) = invokeStatic(
                "com.onyx.android.sdk.device.EpdController", "invalidateScreen", a,
                altMethods = listOf("partialRefresh"))
            override fun test(a: Activity) = classExists(
                "com.onyx.android.sdk.device.EpdController",
                listOf("requestEpdMode", "fullRefresh", "invalidateScreen", "resetScreen"))
        },
        object : RefreshEntry {
            override val vendor = "onyx.EpdDeviceManager"
            override fun full(a: Activity) = invokeStatic(
                "com.onyx.android.sdk.api.device.EpdDeviceManager", "resetScreen", a,
                altMethods = listOf("fullRefresh", "invalidate"))
            override fun partial(a: Activity) = invokeStatic(
                "com.onyx.android.sdk.api.device.EpdDeviceManager", "invalidate", a)
            override fun test(a: Activity) = classExists(
                "com.onyx.android.sdk.api.device.EpdDeviceManager",
                listOf("resetScreen", "fullRefresh", "invalidate"))
        },
        object : RefreshEntry {
            override val vendor = "onyx.DeviceInfoSingleton"
            override fun full(a: Activity) = invokeSingleton(
                "com.onyx.android.sdk.device.DeviceInfoSingleton", "getDevice", a,
                listOf("resetScreen", "fullRefresh", "refreshScreen"))
            override fun partial(a: Activity) = invokeSingleton(
                "com.onyx.android.sdk.device.DeviceInfoSingleton", "getDevice", a,
                listOf("invalidate", "partialRefresh"))
            override fun test(a: Activity) = classExists(
                "com.onyx.android.sdk.device.DeviceInfoSingleton",
                listOf("getDevice"))
        },
        // ---- 海信 ----
        object : RefreshEntry {
            override val vendor = "hisense.Epd"
            override fun full(a: Activity) = invokeStatic(
                "com.hisense.epd.Epd", "fullRefresh", a,
                altMethods = listOf("screenUpdate", "setRefreshMode"))
            override fun partial(a: Activity) = invokeStatic(
                "com.hisense.epd.Epd", "partialRefresh", a,
                altMethods = listOf("screenUpdate"))
            override fun test(a: Activity) = classExists(
                "com.hisense.epd.Epd",
                listOf("fullRefresh", "partialRefresh", "screenUpdate", "setRefreshMode"))
        },
        object : RefreshEntry {
            override val vendor = "hisense.EPDManager"
            override fun full(a: Activity) = invokeStatic(
                "com.hisense.android.graphics.EPDManager", "fullRefresh", a,
                altMethods = listOf("updateScreen"))
            override fun partial(a: Activity) = invokeStatic(
                "com.hisense.android.graphics.EPDManager", "updateScreen", a)
            override fun test(a: Activity) = classExists(
                "com.hisense.android.graphics.EPDManager",
                listOf("fullRefresh", "updateScreen"))
        },
    )

    // ------------------------------------------------------------------
    // 反射工具：方法名逐一尝试，参数只给 (Context) / () 两种常见签名
    // ------------------------------------------------------------------

    private fun invokeStatic(className: String, method: String, activity: Activity,
                             altMethods: List<String> = emptyList()) {
        val clazz = Class.forName(className)
        for (name in listOf(method) + altMethods) {
            if (tryInvoke(clazz, name, activity)) return
        }
        throw NoSuchMethodException("$className#$method")
    }

    private fun invokeSingleton(className: String, getter: String, activity: Activity,
                                methods: List<String>) {
        val clazz = Class.forName(className)
        val instance = clazz.getMethod(getter, android.content.Context::class.java)
            .invoke(null, activity)
        for (name in methods) {
            val m = instance.javaClass.methods.firstOrNull { it.name == name }
            if (m != null) {
                try {
                    m.parameterTypes.size.let { size ->
                        if (size == 1 && m.parameterTypes[0].isAssignableFrom(android.content.Context::class.java)) {
                            m.invoke(instance, activity)
                        } else if (size == 0) {
                            m.invoke(instance)
                        } else if (size == 2) {
                            m.invoke(instance, activity, true)
                        } else null
                    }
                    return
                } catch (_: Throwable) { /* 下一个 */ }
            }
        }
        throw NoSuchMethodException("$className#$getter -> $methods")
    }

    private fun tryInvoke(clazz: Class<*>, name: String, activity: Activity): Boolean {
        val ctx = android.content.Context::class.java
        for (m in clazz.methods.filter { it.name == name }) {
            try {
                val size = m.parameterTypes.size
                val applicable = when (size) {
                    0 -> true
                    1 -> m.parameterTypes[0].isAssignableFrom(ctx)
                    2 -> m.parameterTypes[0].isAssignableFrom(ctx)
                    else -> false
                }
                if (!applicable) continue
                when (size) {
                    1 -> m.invoke(null, activity)
                    2 -> m.invoke(null, activity, true)
                    else -> m.invoke(null)
                }
                return true
            } catch (_: Throwable) { /* 下一个签名 */ }
        }
        return false
    }

    /** 通用兜底：强制重绘 decorView。真墨水屏在默认局刷模式下等效局刷。 */
    private fun genericFallback(activity: Activity, full: Boolean) {
        activity.runOnUiThread {
            val decor = activity.window.decorView
            decor.invalidate()
            decor.postInvalidate()
            if (full) decor.requestLayout()
        }
    }
}
