package com.shouba.sales_assistant

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileOutputStream

/**
 * 截图辅助类
 */
class ScreenshotHelper(private val service: android.accessibilityservice.AccessibilityService) {
    
    private val TAG = "ScreenshotHelper"
    private val PREFS_NAME = "FlutterSharedPreferences"
    
    fun takeScreenshot() {
        val sdkVersion = Build.VERSION.SDK_INT
        Log.d(TAG, "📸 开始截图 - Android SDK: $sdkVersion")
        
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                Log.d(TAG, "   → 使用 Android 11+ 无障碍截图 API")
                takeScreenshotModern()
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P -> {
                Log.d(TAG, "   → 使用 Android 9+ 无障碍截图 API（可能不稳定）")
                takeScreenshotModern()
            }
            else -> {
                Log.e(TAG, "❌ Android 版本过低 (< 9.0)，不支持无声截图")
                notifyScreenshotError("Android 版本过低，需要 Android 9.0 或更高版本")
            }
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.P)
    private fun takeScreenshotModern() {
        Log.d(TAG, "📸 调用 takeScreenshot API...")
        try {
            service.takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                service.applicationContext.mainExecutor,
                object : android.accessibilityservice.AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: android.accessibilityservice.AccessibilityService.ScreenshotResult) {
                        Log.d(TAG, "✅ takeScreenshot API 成功回调")
                        try {
                            val bitmap = android.graphics.Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace
                            )
                            
                            if (bitmap != null) {
                                saveBitmapToFile(bitmap)
                                screenshot.hardwareBuffer.close()
                            } else {
                                Log.e(TAG, "❌ Bitmap conversion failed")
                                notifyScreenshotError("Bitmap 转换失败")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Screenshot save failed", e)
                            notifyScreenshotError("保存截图失败: ${e.message}")
                        }
                    }
                    
                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "❌ takeScreenshot API 失败, error code: $errorCode")
                        
                        val errorMessage = when (errorCode) {
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR -> 
                                "内部错误"
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT -> 
                                "截图间隔太短，请稍后再试"
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_INVALID_DISPLAY -> 
                                "无效的显示器"
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_INVALID_WINDOW -> 
                                "无效的窗口"
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_NO_ACCESSIBILITY_ACCESS -> 
                                "无障碍权限不足"
                            android.accessibilityservice.AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW -> 
                                "安全窗口无法截图"
                            else -> "未知错误"
                        }
                        
                        Log.e(TAG, "   原因: $errorMessage")
                        notifyScreenshotError("截图失败: $errorMessage")
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ takeScreenshot API 抛出异常: ${e.javaClass.simpleName}", e)
            notifyScreenshotError("截图异常: ${e.message}")
        }
    }
    
    private fun saveBitmapToFile(bitmap: Bitmap) {
        try {
            val timestamp = System.currentTimeMillis()
            val fileName = "screenshot_$timestamp.png"
            val file = File(service.filesDir, fileName)
            
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            
            val fileSize = file.length()
            Log.d(TAG, "✅ 截图文件大小: ${fileSize / 1024} KB")
            
            val responseTime = System.currentTimeMillis()
            Log.d(TAG, "📝 保存截图信息 - 响应时间: $responseTime")
            
            val prefs = service.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            
            editor.putString("flutter.last_screenshot_path", file.absolutePath)
            editor.putLong("flutter.screenshot_timestamp", timestamp)
            editor.putLong("flutter.screenshot_response_time", responseTime)
            editor.putString("flutter.screenshot_response_time_str", responseTime.toString())
            editor.putBoolean("flutter.screenshot_ready", true)
            editor.putBoolean("flutter.screenshot_requested", false)
            editor.commit()
            
            Log.d(TAG, "✅ 截图信息已保存到 SharedPreferences")
            Log.d(TAG, "   - 路径: ${file.absolutePath}")
            Log.d(TAG, "   - 响应时间: $responseTime")
            
            // 发送广播通知
            val intent = Intent("com.shouba.sales_assistant.SCREENSHOT_READY")
            intent.putExtra("path", file.absolutePath)
            intent.putExtra("timestamp", timestamp)
            intent.setPackage(service.packageName)
            service.sendBroadcast(intent)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Save bitmap failed", e)
            notifyScreenshotError("保存截图失败: ${e.message}")
        }
    }
    
    fun notifyScreenshotError(error: String) {
        val prefs = service.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("flutter.screenshot_ready", false)
            .putString("flutter.screenshot_error", error)
            .apply()
    }
}
