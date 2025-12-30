package com.shouba.sales_assistant

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils.SimpleStringSplitter
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.shouba.sales_assistant/overlay"
    private val REQUEST_OVERLAY_PERMISSION = 2
    
    private var methodChannel: MethodChannel? = null
    private var ocrPrefsListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var screenshotReceiver: BroadcastReceiver? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 创建 MethodChannel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // 将 MethodChannel 传递给 OverlayService
        OverlayService.methodChannel = methodChannel
        
        // 注册截图完成广播接收器
        registerScreenshotReceiver()
        
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(hasPermission)
                }
                
                "checkAccessibilityPermission" -> {
                    val hasPermission = isAccessibilityServiceEnabled()
                    result.success(hasPermission)
                }
                
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(null)
                }
                
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (!Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivityForResult(intent, REQUEST_OVERLAY_PERMISSION)
                            result.success(null)
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                
                "showOverlay" -> {
                    val intent = Intent(this, OverlayService::class.java).apply {
                        action = "SHOW_OVERLAY"
                    }
                    startForegroundService(intent)
                    result.success(null)
                }
                
                "hideOverlay" -> {
                    val intent = Intent(this, OverlayService::class.java).apply {
                        action = "HIDE_OVERLAY"
                    }
                    startService(intent)
                    result.success(null)
                }
                
                "autoInputText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "文本不能为空", null)
                        return@setMethodCallHandler
                    }
                    
                    // 通过无障碍服务实现自动输入
                    val service = AccessibilityScreenshotService.getInstance()
                    if (service != null) {
                        val success = service.autoInputText(text)
                        result.success(success)
                    } else {
                        Log.e(TAG, "❌ 无障碍服务未运行")
                        result.error("SERVICE_NOT_RUNNING", "无障碍服务未运行", null)
                    }
                }
                
                "isWeChatActive" -> {
                    // 检查当前是否在微信界面
                    val service = AccessibilityScreenshotService.getInstance()
                    if (service != null) {
                        val isWeChat = service.isWeChatActive()
                        result.success(isWeChat)
                    } else {
                        Log.e(TAG, "❌ 无障碍服务未运行,无法检测当前应用")
                        result.success(false)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        when (requestCode) {
            REQUEST_OVERLAY_PERMISSION -> {
                val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Settings.canDrawOverlays(this)
                } else {
                    true
                }
                methodChannel?.invokeMethod("onOverlayPermissionResult", hasPermission)
            }
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
    
    override fun onResume() {
        super.onResume()
        
        // 注册 OCR 结果监听器
        setupOCRListener()
        
        // 从设置返回时自动刷新权限状态
        Handler(Looper.getMainLooper()).postDelayed({
            val overlayPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(this)
            } else {
                true
            }
            
            // 同时刷新无障碍服务状态
            val accessibilityEnabled = isAccessibilityServiceEnabled()
            
            methodChannel?.invokeMethod("onPermissionsChanged", mapOf(
                "overlay" to overlayPermission,
                "accessibility" to accessibilityEnabled
            ))
        }, 500)
    }
    
    private fun setupOCRListener() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        
        // 移除旧监听器
        ocrPrefsListener?.let { prefs.unregisterOnSharedPreferenceChangeListener(it) }
        
        // 创建新监听器
        ocrPrefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "flutter.ocr_ready") {
                val ready = prefs.getBoolean("flutter.ocr_ready", false)
                if (ready) {
                    val text = prefs.getString("flutter.ocr_text", "") ?: ""
                    
                    // 通知 Flutter
                    methodChannel?.invokeMethod("onOCRComplete", mapOf(
                        "text" to text
                    ))
                    
                    // 清除标志
                    prefs.edit().putBoolean("flutter.ocr_ready", false).apply()
                }
            }
        }
        
        prefs.registerOnSharedPreferenceChangeListener(ocrPrefsListener)
    }
    
    override fun onPause() {
        super.onPause()
        
        // 移除监听器
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        ocrPrefsListener?.let { prefs.unregisterOnSharedPreferenceChangeListener(it) }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // 清理 MethodChannel
        methodChannel?.setMethodCallHandler(null)
        
        // 注销广播接收器
        screenshotReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 注销广播接收器失败", e)
            }
        }
    }
    
    /**
     * 检查无障碍服务是否已启用
     * ✅ 只检查系统设置,不检查服务实例(实例只在应用运行时存在)
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponentName = ComponentName(this, AccessibilityScreenshotService::class.java)
        
        val enabledServicesSetting = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )
        
        if (enabledServicesSetting.isNullOrEmpty()) {
            return false
        }
        
        val colonSplitter = SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)
        
        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            val enabledService = ComponentName.unflattenFromString(componentNameString)
            
            if (enabledService != null && enabledService == expectedComponentName) {
                return true
            }
        }
        
        return false
    }
    
    /**
     * 注册截图完成广播接收器
     */
    private fun registerScreenshotReceiver() {
        screenshotReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == "com.shouba.sales_assistant.SCREENSHOT_READY") {
                    val path = intent.getStringExtra("path")
                    val timestamp = intent.getLongExtra("timestamp", 0)
                    
                    // 方案1: 通过 MethodChannel 直接通知 Flutter (最可靠)
                    Handler(Looper.getMainLooper()).post {
                        val data = mapOf(
                            "path" to path,
                            "timestamp" to timestamp,
                            "ready" to true
                        )
                        methodChannel?.invokeMethod("onScreenshotReady", data)
                    }
                    
                    // 方案2: 同时更新 SharedPreferences (作为备用)
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("flutter.flutter.last_screenshot_path", path)
                        .putLong("flutter.flutter.screenshot_timestamp", timestamp)
                        .putBoolean("flutter.flutter.screenshot_ready", true)
                        .commit()
                }
            }
        }
        
        val filter = IntentFilter("com.shouba.sales_assistant.SCREENSHOT_READY")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenshotReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenshotReceiver, filter)
        }
    }
}
