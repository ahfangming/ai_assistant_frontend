package com.shouba.sales_assistant

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.accessibilityservice.GestureDescription
import androidx.annotation.RequiresApi

class AutoInputHelper(private val service: android.accessibilityservice.AccessibilityService) {
    
    private val TAG = "AutoInputHelper"
    
    fun autoInputText(text: String): Boolean {
        try {
            val clipboardManager = service.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("ai_reply", text)
            clipboardManager.setPrimaryClip(clip)
            
            val uiSuccess = trySetTextViaUiAutomation(text)
            if (uiSuccess) {
                (service as? AccessibilityScreenshotService)?.vibrate(100)
                return true
            }
            
            Log.w(TAG, "⚠️ UiAutomation failed, trying coordinate-based input...")
            return tryClickInputByCoordinates(text)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Auto input exception", e)
            return false
        }
    }
    
    private fun trySetTextViaUiAutomation(text: String): Boolean {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                Log.w(TAG, "⚠️ Android version too low (< 7.0)")
                return false
            }
            
            val rootNode = service.rootInActiveWindow
            if (rootNode != null) {
                val inputNode = findEditableNode(rootNode)
                
                if (inputNode != null) {
                    val arguments = Bundle()
                    arguments.putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, 
                        text
                    )
                    val success = inputNode.performAction(
                        AccessibilityNodeInfo.ACTION_SET_TEXT, 
                        arguments
                    )
                    
                    inputNode.recycle()
                    rootNode.recycle()
                    
                    if (success) {
                        return true
                    } else {
                        Log.w(TAG, "⚠️ ACTION_SET_TEXT execution failed")
                    }
                } else {
                    Log.w(TAG, "⚠️ No editable node found")
                    rootNode.recycle()
                }
            } else {
                Log.w(TAG, "⚠️ Unable to get root node")
            }
            
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ UiAutomation setText failed", e)
            return false
        }
    }
    
    private fun findEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        
        if (node.isEditable && node.isFocused) {
            return node
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val result = findEditableNode(child)
            if (result != null) {
                child?.recycle()
                return result
            }
            child?.recycle()
        }
        
        return null
    }
    
    private fun tryClickInputByCoordinates(text: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "⚠️ Android version too low (< 7.0), gesture not supported")
            return false
        }
        
        try {
            val windowManager = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val displayMetrics = DisplayMetrics()
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            
            val navigationBarHeight = getNavigationBarHeight()
            
            Log.d(TAG, "📱 屏幕尺寸: ${screenWidth}x${screenHeight}")
            Log.d(TAG, "📱 导航栏高度: ${navigationBarHeight}px")
            
            Log.d(TAG, "📍 使用固定坐标进行点击（微信限制了节点访问）")
            
            val firstClickX = (screenWidth * 0.4).toInt()
            val firstClickY = if (navigationBarHeight < screenHeight - 200) {
                screenHeight - navigationBarHeight - 100  
            } else {
                screenHeight - 100  
            }
            
            Log.d(TAG, "📱 第1次点击（唤起键盘）: X=$firstClickX, Y=$firstClickY")
            val clicked = performClick(firstClickX.toFloat(), firstClickY.toFloat(), 50)
            if (!clicked) {
                Log.e(TAG, "❌ 第1次点击失败")
                return false
            }
            
            Thread.sleep(400)
            
            val secondClickX = (screenWidth * 0.4).toInt()
            val keyboardHeight = 800  
            val secondClickY = screenHeight - keyboardHeight - navigationBarHeight - 100
            
            Log.d(TAG, "📱 第2次长按（唤起粘贴菜单）: X=$secondClickX, Y=$secondClickY")
            
            val longPressed = performLongClick(secondClickX.toFloat(), secondClickY.toFloat())
            if (!longPressed) {
                Log.w(TAG, "⚠️ 第2次长按失败")
                return false
            }
            
            Thread.sleep(300)
            
            val menuAppeared = checkIfMenuAppeared()
            if (menuAppeared) {
                Log.d(TAG, "✅ 检测到粘贴菜单已弹出")
            } else {
                Log.d(TAG, "⏳ 未检测到菜单，但继续尝试点击")
            }
            
            val pasteButtonCoords = findPasteButtonCoordinates()
            if (pasteButtonCoords != null) {
                val (btnX, btnY) = pasteButtonCoords
                Log.d(TAG, "🎯 找到粘贴按钮实际位置: X=$btnX, Y=$btnY")
                
                val clicked = performClick(btnX, btnY, 150)
                if (clicked) {
                    Thread.sleep(300)  
                    
                    val menuNodes = mutableListOf<String>()
                    val rootCheck = service.rootInActiveWindow
                    val menuStillExists = if (rootCheck != null) {
                        val result = hasMenuNodes(rootCheck, menuNodes)
                        rootCheck.recycle()
                        result
                    } else {
                        false
                    }
                    
                    if (!menuStillExists) {
                        Log.d(TAG, "✅ 通过按钮实际坐标粘贴成功!")
                        (service as? AccessibilityScreenshotService)?.vibrate(100)
                        return true
                    } else {
                        Log.w(TAG, "⚠️ 点击后菜单仍存在: ${menuNodes.joinToString(", ")}")
                    }
                }
            } else {
                Log.w(TAG, "⚠️ 未能获取粘贴按钮实际坐标，使用预设位置")
            }
            
            val pasteButtonBaseY = secondClickY - 120  
            
            Log.d(TAG, "📍 粘贴菜单基准位置: Y=$pasteButtonBaseY (输入框Y=$secondClickY)")
            
            val positions = listOf(
                Pair(80, pasteButtonBaseY - 20),
                Pair(50, pasteButtonBaseY - 20),
                Pair(110, pasteButtonBaseY - 20),
                Pair(80, pasteButtonBaseY),
                Pair(50, pasteButtonBaseY),
                Pair(110, pasteButtonBaseY),
                Pair(80, pasteButtonBaseY + 20),
                Pair(50, pasteButtonBaseY + 20),
                Pair(110, pasteButtonBaseY + 20),
                Pair(30, pasteButtonBaseY),
                Pair(30, pasteButtonBaseY - 20),
                Pair(150, pasteButtonBaseY),
                Pair(150, pasteButtonBaseY - 20)
            )
            
            Log.d(TAG, "📍 准备尝试 ${positions.size} 个粘贴按钮位置...")
            
            for ((index, pos) in positions.withIndex()) {
                val (btnX, btnY) = pos
                
                Log.d(TAG, "   位置${index+1}: X=$btnX, Y=$btnY")
                
                val clicked = performClick(btnX.toFloat(), btnY.toFloat(), 100)
                
                if (clicked) {
                    Thread.sleep(250)  
                    
                    val menuNodesAfter = mutableListOf<String>()
                    val rootAfter = service.rootInActiveWindow
                    val menuGone = if (rootAfter != null) {
                        val result = !hasMenuNodes(rootAfter, menuNodesAfter)
                        rootAfter.recycle()
                        result
                    } else {
                        true  
                    }
                    
                    if (menuGone) {
                        Log.d(TAG, "✅ 位置${index+1}成功! (X=$btnX, Y=$btnY)")
                        (service as? AccessibilityScreenshotService)?.vibrate(100)
                        
                        Thread.sleep(200)
                        return true
                    } else {
                        Log.d(TAG, "   位置${index+1}点击后菜单仍存在: ${menuNodesAfter.joinToString(", ")}")
                    }
                }
                
                if (index < positions.size - 1) {
                    Thread.sleep(50)
                }
            }
            
            Log.w(TAG, "⚠️ 尝试了${positions.size}个位置仍未成功")
            
            val nodePasteSuccess = tryPasteViaNodeAction()
            if (nodePasteSuccess) {
                Log.d(TAG, "✅ 节点粘贴成功")
                (service as? AccessibilityScreenshotService)?.vibrate(100)
                return true
            }
            
            Log.w(TAG, "⚠️ 所有策略均失败")
            Log.w(TAG, "⚠️ 文本已在剪贴板，请手动粘贴")
            return false
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Coordinate-based input failed", e)
            return false
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.N)
    private fun performClick(x: Float, y: Float, duration: Long = 150): Boolean {
        return try {
            val path = Path()
            path.moveTo(x, y)
            
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
                .build()
            
            val result = service.dispatchGesture(gesture, null, null)
            
            if (!result) {
                Log.w(TAG, "      ⚠️ dispatchGesture 返回 false")
                return false
            }
            
            Thread.sleep(duration + 50)
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Click gesture failed", e)
            false
        }
    }
    
    @RequiresApi(Build.VERSION_CODES.N)
    private fun performLongClick(x: Float, y: Float): Boolean {
        return try {
            val path = Path()
            path.moveTo(x, y)
            
            val gesture = GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, 800))
                .build()
            
            service.dispatchGesture(gesture, null, null)
            Thread.sleep(800)
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Long click failed", e)
            false
        }
    }
    
    private fun tryPasteViaNodeAction(): Boolean {
        return try {
            val rootNode = service.rootInActiveWindow ?: return false
            
            val editableNodes = mutableListOf<AccessibilityNodeInfo>()
            findEditableNodes(rootNode, editableNodes)
            
            for (node in editableNodes) {
                if (node.isEditable && node.isFocused) {
                    val pasteSuccess = node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                    
                    if (pasteSuccess) {
                        node.recycle()
                        editableNodes.forEach { it.recycle() }
                        rootNode.recycle()
                        return true
                    } else {
                        Log.w(TAG, "   ⚠️ ACTION_PASTE 返回 false")
                    }
                }
            }
            
            editableNodes.forEach { it.recycle() }
            rootNode.recycle()
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Node paste failed", e)
            false
        }
    }
    
    private fun findEditableNodes(node: AccessibilityNodeInfo?, result: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        
        if (node.isEditable) {
            result.add(node)
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            findEditableNodes(child, result)
            child?.recycle()
        }
    }
    
    private fun checkIfMenuAppeared(): Boolean {
        return try {
            val rootNode = service.rootInActiveWindow ?: return false
            
            val menuNodes = mutableListOf<String>()
            val hasMenu = hasMenuNodes(rootNode, menuNodes)
            rootNode.recycle()
            
            if (hasMenu && menuNodes.isNotEmpty()) {
                Log.d(TAG, "🔍 检测到菜单节点: ${menuNodes.joinToString(", ")}")
            }
            
            hasMenu
        } catch (e: Exception) {
            Log.e(TAG, "❌ Menu detection failed", e)
            false
        }
    }
    
    private fun hasMenuNodes(node: AccessibilityNodeInfo?, foundNodes: MutableList<String>): Boolean {
        if (node == null) return false
        
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""
        
        val menuKeywords = listOf("粘贴", "paste", "复制", "copy", "剪切", "cut", "全选", "select")
        val hasKeyword = menuKeywords.any { 
            text.contains(it, ignoreCase = true) || desc.contains(it, ignoreCase = true)
        }
        
        if (hasKeyword) {
            val nodeInfo = when {
                text.isNotEmpty() -> "text='$text'"
                desc.isNotEmpty() -> "desc='$desc'"
                else -> "unknown"
            }
            foundNodes.add(nodeInfo)
            return true
        }
        
        var found = false
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (hasMenuNodes(child, foundNodes)) {
                found = true
            }
            child?.recycle()
        }
        
        return found
    }
    
    private fun findPasteButtonCoordinates(): Pair<Float, Float>? {
        return try {
            val rootNode = service.rootInActiveWindow ?: return null
            
            val pasteButton = findPasteButtonRecursive(rootNode)
            
            if (pasteButton != null) {
                val rect = android.graphics.Rect()
                pasteButton.getBoundsInScreen(rect)
                
                val x = rect.centerX().toFloat()
                val y = rect.centerY().toFloat()
                
                Log.d(TAG, "🔍 粘贴按钮节点信息:")
                Log.d(TAG, "   - 位置: (${rect.left}, ${rect.top}) -> (${rect.right}, ${rect.bottom})")
                Log.d(TAG, "   - 中心点: ($x, $y)")
                Log.d(TAG, "   - 文本: ${pasteButton.text}")
                Log.d(TAG, "   - 描述: ${pasteButton.contentDescription}")
                Log.d(TAG, "   - 类名: ${pasteButton.className}")
                Log.d(TAG, "   - 可点击: ${pasteButton.isClickable}")
                
                pasteButton.recycle()
                rootNode.recycle()
                
                return Pair(x, y)
            }
            
            rootNode.recycle()
            null
        } catch (e: Exception) {
            Log.e(TAG, "❌ 查找粘贴按钮坐标失败", e)
            null
        }
    }
    
    private fun findAndClickPasteButton(): Boolean {
        return try {
            val rootNode = service.rootInActiveWindow ?: run {
                Log.w(TAG, "⚠️ 无法获取屏幕根节点")
                return false
            }
            
            val pasteButton = findPasteButtonRecursive(rootNode)
            rootNode.recycle()
            
            if (pasteButton != null) {
                val clicked = pasteButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                pasteButton.recycle()
                
                if (clicked) {
                    return true
                } else {
                    Log.w(TAG, "⚠️ 粘贴按钮点击失败")
                }
            } else {
                Log.w(TAG, "⚠️ 未找到粘贴按钮")
            }
            
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Find paste button failed", e)
            false
        }
    }
    
    private fun findPasteButtonRecursive(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        
        val text = node.text?.toString() ?: ""
        val contentDesc = node.contentDescription?.toString() ?: ""
        
        val isPasteButton = (
            text.contains("粘贴", ignoreCase = true) ||
            text.contains("paste", ignoreCase = true) ||
            contentDesc.contains("粘贴", ignoreCase = true) ||
            contentDesc.contains("paste", ignoreCase = true) ||
            (node.viewIdResourceName?.contains("paste", ignoreCase = true) == true)
        ) && (node.isClickable || node.isFocusable || node.isLongClickable)
        
        if (isPasteButton) {
            return node
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val result = findPasteButtonRecursive(child)
            if (result != null) {
                child?.recycle()
                return result
            }
            child?.recycle()
        }
        
        return null
    }
    
    private fun dumpNodeTree(node: AccessibilityNodeInfo?, depth: Int) {
        if (node == null) return
        
        val indent = "  ".repeat(depth)
        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        val clickable = if (node.isClickable) "✓" else "✗"
        
        if (text.isNotEmpty() || desc.isNotEmpty()) {
            Log.d(TAG, "$indent[$className] text='$text' desc='$desc' clickable=$clickable")
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            dumpNodeTree(child, depth + 1)
            child?.recycle()
        }
    }
    
    private fun collectEditableNodes(node: AccessibilityNodeInfo?, list: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        
        if (node.isEditable) {
            list.add(node)
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            collectEditableNodes(child, list)
            child?.recycle()
        }
    }
    
    fun findWeChatInputBox(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        
        val editableNodes = mutableListOf<AccessibilityNodeInfo>()
        collectEditableNodes(node, editableNodes)
        
        val wechatNode = editableNodes.firstOrNull { editNode ->
            val packageName = editNode.packageName?.toString() ?: ""
            val viewId = editNode.viewIdResourceName ?: ""
            
            packageName.contains("com.tencent.mm", ignoreCase = true) &&
            (viewId.contains("input", ignoreCase = true) || 
             viewId.contains("edit", ignoreCase = true) ||
             viewId.contains("al_", ignoreCase = true) ||
             viewId.contains("chat", ignoreCase = true))
        }
        
        if (wechatNode != null) {
            return wechatNode
        }
        
        val wechatPackageNode = editableNodes.firstOrNull { editNode ->
            val packageName = editNode.packageName?.toString() ?: ""
            packageName.contains("com.tencent.mm", ignoreCase = true)
        }
        
        if (wechatPackageNode != null) {
            return wechatPackageNode
        }
        
        val editTextNode = editableNodes.firstOrNull { editNode ->
            val className = editNode.className?.toString() ?: ""
            className.contains("EditText", ignoreCase = true) ||
            className.contains("TextInputEditText", ignoreCase = true)
        }
        
        if (editTextNode != null) {
            return editTextNode
        }
        
        val focusableNode = editableNodes.firstOrNull { it.isFocusable }
        if (focusableNode != null) {
            return focusableNode
        }
        
        return editableNodes.firstOrNull()
    }
    
    private fun getNavigationBarHeight(): Int {
        return try {
            val windowManager = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val displayMetrics = DisplayMetrics()
            
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
            val realHeight = displayMetrics.heightPixels
            
            windowManager.defaultDisplay.getMetrics(displayMetrics)
            val usableHeight = displayMetrics.heightPixels
            
            val statusBarHeight = getStatusBarHeight()
            
            val totalGap = realHeight - usableHeight
            
            val navigationBarHeight = totalGap - statusBarHeight
            
            if (navigationBarHeight < 50) {
                Log.d(TAG, "✅ 检测到全面屏手势，忽略手势条高度")
                return 0
            } else {
                Log.d(TAG, "✅ 检测到传统导航栏，高度: ${navigationBarHeight}px")
                return navigationBarHeight
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ 获取导航栏高度失败", e)
            0  
        }
    }
    
    private fun getStatusBarHeight(): Int {
        return try {
            val resources = service.resources
            val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
            if (resourceId > 0) {
                resources.getDimensionPixelSize(resourceId)
            } else {
                0
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 获取状态栏高度失败", e)
            0
        }
    }
}
