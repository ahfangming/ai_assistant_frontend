import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../services/ai_service.dart';
import '../../services/screen_capture_service.dart';
import '../../services/auto_input_service.dart';

/// 首页 - AI 销售助手主界面
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.shouba.sales_assistant/overlay');
  
  bool _hasOverlayPermission = false;
  bool _hasAccessibilityPermission = false;
  bool _isOverlayVisible = false;
  bool _userManuallyClosed = false; // 记录用户是否手动关闭过
  AIRole _selectedRole = AIRole.chat; // 当前选择的角色
  
  Timer? _permissionCheckTimer;
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
    platform.setMethodCallHandler(_handleMethodCall);
    _startPermissionCheckTimer();
  }
  
  Future<void> _checkPermissions() async {
    await _checkOverlayPermission();
    await _checkAccessibilityPermission();
    _autoShowOverlayIfReady();
  }
  
  Future<void> _checkOverlayPermission() async {
    try {
      final bool hasPermission = await platform.invokeMethod('checkOverlayPermission');
      setState(() {
        _hasOverlayPermission = hasPermission;
      });
    } catch (e) {
      debugPrint('Check overlay permission failed: $e');
    }
  }
  
  Future<void> _checkAccessibilityPermission() async {
    try {
      final bool hasPermission = await platform.invokeMethod('checkAccessibilityPermission');
      setState(() {
        _hasAccessibilityPermission = hasPermission;
      });
    } catch (e) {
      debugPrint('Check accessibility permission failed: $e');
      setState(() {
        _hasAccessibilityPermission = false;
      });
    }
  }
  
  void _startPermissionCheckTimer() {
    _permissionCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkPermissions();
    });
  }
  
  @override
  void dispose() {
    _permissionCheckTimer?.cancel();
    super.dispose();
  }

  /// 处理来自平台的消息
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotRequested':
        _executeFullFlow();
        break;
        
      case 'onScreenshotReady':
        final data = call.arguments as Map;
        final path = data['path'] as String?;
        final ready = data['ready'] as bool? ?? false;
        
        if (path != null && ready) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('flutter.last_screenshot_path', path);
          await prefs.setBool('flutter.screenshot_ready', true);
        }
        break;
        
      case 'onPermissionsChanged':
        final data = call.arguments as Map;
        setState(() {
          _hasOverlayPermission = data['overlay'] as bool;
          if (data.containsKey('accessibility')) {
            _hasAccessibilityPermission = data['accessibility'] as bool;
          }
        });
        _autoShowOverlayIfReady();
        break;
    }
  }
  
  /// 请求悬浮窗权限
  Future<void> _requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Request permission failed: $e');
    }
  }
  
  /// 请求无障碍服务权限
  Future<void> _requestAccessibilityPermission() async {
    try {
      await platform.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugPrint('Request accessibility permission failed: $e');
    }
  }
  
  /// 如果权限就绪且悬浮窗未显示，自动显示悬浮窗（除非用户手动关闭过）
  Future<void> _autoShowOverlayIfReady() async {
    // 只有在权限就绪、悬浮窗未显示、且用户未手动关闭时才自动显示
    if (_hasOverlayPermission && _hasAccessibilityPermission && !_isOverlayVisible && !_userManuallyClosed) {
      await _showOverlay();
    }
  }
  
  /// 显示悬浮窗
  Future<void> _showOverlay() async {
    if (!_hasOverlayPermission) {
      await _requestOverlayPermission();
      return;
    }
    
    try {
      await platform.invokeMethod('showOverlay');
      setState(() {
        _isOverlayVisible = true;
        _userManuallyClosed = false; // 显示时重置标记
      });
    } catch (e) {
      debugPrint('显示悬浮窗失败: $e');
    }
  }
  
  /// 隐藏悬浮窗
  Future<void> _hideOverlay() async {
    try {
      await platform.invokeMethod('hideOverlay');
      setState(() {
        _isOverlayVisible = false;
        _userManuallyClosed = true; // 标记为用户手动关闭
      });
    } catch (e) {
      debugPrint('Hide overlay failed: $e');
    }
  }
  
  /// 执行完整的截图、OCR、AI生成回复、自动输入流程
  Future<void> _executeFullFlow() async {
    print('🚀 [HomePage] 收到截图请求，开始执行完整流程...');
    
    try {
      // 步骤0: 检查当前是否在微信界面
      print('🔍 [HomePage] 检查当前界面...');
      final isWeChat = await AutoInputService.isWeChatActive();
      print(isWeChat ? '✅ [HomePage] 当前在微信界面' : '⚠️ [HomePage] 当前不在微信界面');
      
      // 步骤1: 使用 ScreenCaptureService 进行截图和 OCR 识别
      print('📸 [HomePage] 调用 ScreenCaptureService...');
      final ocrText = await ScreenCaptureService.captureAndRecognize();
      
      if (ocrText.isEmpty) {
        print('⚠️ [HomePage] OCR 识别结果为空，终止流程');
        return;
      }
      
      print('✅ [HomePage] OCR 识别成功，文本长度: ${ocrText.length} 字符');
      
      // 步骤2: AI生成回复
      print('🤖 [HomePage] 调用 AI 服务生成回复...');
      final aiService = AIService();
      final aiReply = await aiService.generateWeChatReply(ocrText, role: _selectedRole);
      
      if (aiReply.isEmpty) {
        print('⚠️ [HomePage] AI 回复为空，终止流程');
        return;
      }
      
      print('✅ [HomePage] AI 生成成功（角色：${_selectedRole.displayName}），回复长度: ${aiReply.length} 字符');
      print('📝 [HomePage] AI 回复内容: $aiReply');
      
      // 步骤3: 根据是否在微信界面选择不同的处理方式
      await AutoInputService.copyToClipboard(aiReply);
      
      if (isWeChat) {
        // 在微信界面：执行完整的自动输入流程
        print('⌨️ [HomePage] 在微信界面，开始自动输入...');
        
        // 等待界面稳定（给无障碍服务时间获取节点树）
        print('⏳ [HomePage] 等待界面稳定...');
        await Future.delayed(const Duration(milliseconds: 300));
        
        await AutoInputService.inputTextToWechat(aiReply);
        print('✅ [HomePage] 自动输入完成！');
      } else {
        // 不在微信界面：只复制到剪贴板
        print('📋 [HomePage] 不在微信界面，内容已复制到剪贴板，请手动粘贴');
      }
      
      print('✅ [HomePage] 完整流程执行完成！');
      
    } catch (e) {
      print('❌ [HomePage] 流程执行失败: $e');
      debugPrint('❌ 流程执行失败: $e');
    }
  }

  /// 构建 UI
  @override
  Widget build(BuildContext context) {
    final bool allPermissionsGranted = _hasOverlayPermission && _hasAccessibilityPermission;
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 销售助手'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题区域 - 更紧凑
              Icon(
                Icons.psychology,
                size: 60,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              
              Text(
                'AI 销售助手',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              
              Text(
                allPermissionsGranted ? '✅ 已就绪' : '⚠️ 需要授权',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: allPermissionsGranted ? theme.colorScheme.primary : theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 角色选择区域
              Text(
                '选择助手角色',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildRoleSelector(context),
              
              const SizedBox(height: 24),
              
              // 权限卡片 - 更紧凑
              _buildCompactPermissionCard(
                context: context,
                icon: Icons.bubble_chart,
                title: '悬浮窗',
                isGranted: _hasOverlayPermission,
                onTap: _hasOverlayPermission ? null : _requestOverlayPermission,
              ),
              
              const SizedBox(height: 12),
              
              _buildCompactPermissionCard(
                context: context,
                icon: Icons.accessibility_new,
                title: '无障碍',
                isGranted: _hasAccessibilityPermission,
                onTap: _hasAccessibilityPermission ? null : _requestAccessibilityPermission,
              ),
              
              const SizedBox(height: 24),
              
              // 状态提示区域
              if (!allPermissionsGranted)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.secondary, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '请点击上方完成授权',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (allPermissionsGranted && _isOverlayVisible)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,  // 最小化高度
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selectedRole.icon} ${_selectedRole.displayName}已启动',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '可以最小化此应用,前往微信使用',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _hideOverlay,
                          icon: const Icon(Icons.visibility_off, size: 18),
                          label: const Text('隐藏悬浮窗'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.secondary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (allPermissionsGranted && !_isOverlayVisible)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showOverlay,
                    icon: const Icon(Icons.play_arrow),
                    label: Text('启动 ${_selectedRole.icon} ${_selectedRole.displayName}'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建角色选择器
  Widget _buildRoleSelector(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: AIRole.values.map((role) {
        final isSelected = _selectedRole == role;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedRole = role;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.outline.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      role.icon,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected 
                            ? theme.colorScheme.onPrimary 
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
  
  /// 构建紧凑的权限卡片组件
  Widget _buildCompactPermissionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool isGranted,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isGranted 
              ? theme.colorScheme.primary.withOpacity(0.3) 
              : theme.colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: isGranted ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                isGranted ? Icons.check_circle : Icons.cancel,
                size: 20,
                color: isGranted ? theme.colorScheme.primary : theme.colorScheme.secondary,
              ),
              if (!isGranted) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建权限卡片组件
  Widget _buildPermissionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool isGranted,
    required String description,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final cardColor = isGranted ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isGranted ? theme.colorScheme.primary.withOpacity(0.3) : theme.colorScheme.outline.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: cardColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isGranted ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color: isGranted ? theme.colorScheme.primary : theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: isGranted ? theme.colorScheme.primary : theme.colorScheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isGranted)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
