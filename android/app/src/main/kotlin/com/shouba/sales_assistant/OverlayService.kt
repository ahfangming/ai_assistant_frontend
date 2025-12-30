package com.shouba.sales_assistant

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * 原生悬浮窗服务 - 在主进程中运行,通过 MethodChannel 与 Flutter 通信
 */
class OverlayService : Service() {
    private val TAG = "OverlayService"
    private val NOTIFICATION_ID = 2001
    private val CHANNEL_ID = "overlay_service"
    
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    
    companion object {
        var methodChannel: MethodChannel? = null
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 悬浮窗服务启动")
        
        createNotificationChannel()
        
        // 使用 specialUse 类型启动前台服务
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                createNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
        
        Log.d(TAG, "✅ 悬浮窗服务初始化完成")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📥 onStartCommand: action=${intent?.action}")
        
        when (intent?.action) {
            "SHOW_OVERLAY" -> {
                Log.d(TAG, "🎯 收到显示悬浮窗命令")
                showOverlay()
            }
            "HIDE_OVERLAY" -> {
                Log.d(TAG, "🎯 收到隐藏悬浮窗命令")
                hideOverlay()
            }
        }
        
        return START_STICKY
    }
    
    /**
     * 显示悬浮窗
     */
    private fun showOverlay() {
        try {
            Log.d(TAG, "🔨 开始创建悬浮窗...")
            
            // 如果已存在,先移除
            if (overlayView != null) {
                Log.d(TAG, "🔄 移除旧悬浮窗")
                try {
                    windowManager?.removeView(overlayView)
                } catch (e: Exception) {
                    Log.e(TAG, "移除悬浮窗失败", e)
                }
                overlayView = null
            }
            
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            Log.d(TAG, "✅ WindowManager 已获取")
            
            // 创建悬浮窗视图 - 使用自定义圆形渐变设计
            overlayView = createModernOverlayView()
            
            Log.d(TAG, "✅ 视图已创建")
            
            // 设置悬浮窗参数
            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            
            val params = WindowManager.LayoutParams(
                dpToPx(56),  // 固定宽度 56dp (更小)
                dpToPx(56),  // 固定高度 56dp (更小)
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = 20
                y = 200
            }
            
            Log.d(TAG, "✅ 参数已配置: type=$layoutFlag")
            
            // 添加到窗口管理器
            windowManager?.addView(overlayView, params)
            Log.d(TAG, "✅ 悬浮窗已显示")
            
            // 通知 Flutter
            methodChannel?.invokeMethod("onOverlayShown", null)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 显示悬浮窗失败", e)
            methodChannel?.invokeMethod("onOverlayError", "显示悬浮窗失败: ${e.message}")
        }
    }
    
    /**
     * 隐藏悬浮窗
     */
    private fun hideOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
                overlayView = null
                Log.d(TAG, "✅ 悬浮窗已隐藏")
                methodChannel?.invokeMethod("onOverlayHidden", null)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 隐藏悬浮窗失败", e)
            }
        }
    }
    
    /**
     * 创建现代化的悬浮窗视图
     */
    private fun createModernOverlayView(): View {
        // 创建容器 - 不设置 layoutParams,由 WindowManager 控制大小
        val container = FrameLayout(this)
        
        // 背景圆形视图 - 这个才是真正的圆形按钮
        val backgroundView = View(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            
            // 设置橙色渐变背景 (主题色)
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                colors = intArrayOf(
                    Color.parseColor("#FF6B35"),  // 主橙色渐变起点
                    Color.parseColor("#F7931E")   // 次橙色渐变终点
                )
                gradientType = android.graphics.drawable.GradientDrawable.LINEAR_GRADIENT
                orientation = android.graphics.drawable.GradientDrawable.Orientation.TL_BR
            }
            
            // 添加阴影效果 - 只在圆形周围
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dpToPx(6).toFloat()  // 适度的阴影
                outlineProvider = object : ViewOutlineProvider() {
                    override fun getOutline(view: View, outline: Outline) {
                        // 关键：使用圆形的 outline，阴影就只会在圆形周围
                        outline.setOval(0, 0, view.width, view.height)
                    }
                }
                clipToOutline = true  // 裁剪到圆形
            }
        }
        
        // 文字视图 - 显示"AI"文字
        val textView = android.widget.TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
            
            // 设置"AI"文字
            text = "AI"
            textSize = 20f  // 文字大小
            setTextColor(Color.WHITE)
            
            // 设置粗体
            setTypeface(null, android.graphics.Typeface.BOLD)
            
            // 设置高 elevation 确保在最上层
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dpToPx(10).toFloat()
            }
        }
        
        // 添加视图（先添加背景，再添加文字）
        container.addView(backgroundView)
        container.addView(textView)
        
        // 点击事件
        container.setOnClickListener {
            Log.d(TAG, "📱 悬浮窗被点击")
            onOverlayClicked()
        }
        
        // 不使用涟漪效果，避免覆盖图标
        
        return container
    }
    
    /**
     * dp 转 px
     */
    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density).toInt()
    }
    
    /**
     * 悬浮窗被点击
     */
    private fun onOverlayClicked() {
        Log.d(TAG, "📱 悬浮窗被点击")
        
        // 先隐藏悬浮窗（避免截图包含悬浮窗）
        overlayView?.visibility = android.view.View.INVISIBLE
        Log.d(TAG, "悬浮窗已隐藏")
        
        // 50ms 后通知 Flutter 开始截图流程
        // 只通知 Flutter，不在 Native 层写入 SharedPreferences，避免重复触发
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            Log.d(TAG, "📸 通知 Flutter 开始截图流程")
            methodChannel?.invokeMethod("onScreenshotRequested", null)
        }, 50)
        
        // 1.5秒后恢复悬浮窗显示
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            overlayView?.visibility = android.view.View.VISIBLE
            Log.d(TAG, "👁️ 悬浮窗已恢复显示")
        }, 1500)
    }
    
    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "悬浮窗服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持悬浮窗运行"
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    /**
     * 创建前台服务通知
     */
    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AI 销售助手")
            .setContentText("悬浮窗服务运行中")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        Log.d(TAG, "🛑 悬浮窗服务已停止")
    }
}
