package com.shouba.sales_assistant

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AccessibilityScreenshotService : AccessibilityService() {
    
    private val TAG = "AccessibilityScreenshot"
    private val PREFS_NAME = "FlutterSharedPreferences"
    
    private lateinit var screenshotHelper: ScreenshotHelper
    private lateinit var autoInputHelper: AutoInputHelper
    
    companion object {
        @Volatile
        private var instance: AccessibilityScreenshotService? = null
        
        fun getInstance(): AccessibilityScreenshotService? = instance
        
        fun isServiceEnabled(context: Context): Boolean {
            return instance != null
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        screenshotHelper = ScreenshotHelper(this)
        autoInputHelper = AutoInputHelper(this)
        Log.d(TAG, "✅ 服务已创建")
    }
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        startListeningForScreenshotRequests()
        Log.d(TAG, "✅ 服务已连接")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    
    override fun onInterrupt() {}
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
    
    private fun startListeningForScreenshotRequests() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val handler = Handler(Looper.getMainLooper())
        
        val checkRunnable = object : Runnable {
            override fun run() {
                try {
                    if (prefs.getBoolean("flutter.screenshot_requested", false)) {
                        prefs.edit().putBoolean("flutter.screenshot_requested", false).apply()
                        screenshotHelper.takeScreenshot()
                    }
                    handler.postDelayed(this, 50L)
                } catch (e: Exception) {
                    Log.e(TAG, "Polling error", e)
                    handler.postDelayed(this, 50L)
                }
            }
        }
        handler.post(checkRunnable)
    }
    
    fun autoInputText(text: String): Boolean {
        return autoInputHelper.autoInputText(text)
    }
    
    fun getCurrentPackageName(): String? {
        return try {
            val rootNode = rootInActiveWindow
            val packageName = rootNode?.packageName?.toString()
            rootNode?.recycle()
            
            Log.d(TAG, "当前前台应用: $packageName")
            packageName
        } catch (e: Exception) {
            Log.e(TAG, "获取前台应用包名失败", e)
            null
        }
    }
    
    fun isWeChatActive(): Boolean {
        val packageName = getCurrentPackageName()
        val isWeChat = packageName == "com.tencent.mm"
        Log.d(TAG, "是否在微信界面: $isWeChat (当前包名: $packageName)")
        return isWeChat
    }
    
    fun vibrate(milliseconds: Long) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(milliseconds)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibrate error", e)
        }
    }
}
