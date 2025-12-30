import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AutoInputService {
  static const platform = MethodChannel('com.shouba.sales_assistant/overlay');

  /// 在微信聊天框中自动输入文本
  /// 通过无障碍服务实现自动粘贴和输入
  /// 
  /// 工作原理：
  /// 1. 将文本复制到剪贴板
  /// 2. 查找并点击微信输入框
  /// 3. 尝试多种方式输入：直接设置、粘贴、全局粘贴
  /// 4. 如果全部失败，文本仍在剪贴板，用户可手动粘贴
  /// 
  /// 返回值：
  /// - true: 自动输入成功
  /// - false: 自动输入失败，但文本已在剪贴板，可手动粘贴
  static Future<bool> inputTextToWechat(String text) async {
    try {
      if (text.isEmpty) {
        return false;
      }
      
      // 调用 Android 原生方法，通过无障碍服务实现自动输入
      final result = await platform.invokeMethod('autoInputText', {
        'text': text,
      });
      
      return result == true;
      
    } catch (e) {
      debugPrint('❌ 自动输入失败: $e');
      return false;
    }
  }
  
  /// 检查当前是否在微信界面
  /// 
  /// 返回值：
  /// - true: 当前在微信界面
  /// - false: 不在微信界面或检测失败
  static Future<bool> isWeChatActive() async {
    try {
      final result = await platform.invokeMethod('isWeChatActive');
      return result == true;
    } catch (e) {
      debugPrint('❌ 检查微信界面失败: $e');
      return false;
    }
  }
  
  /// 检查是否可以自动输入（需要无障碍权限）
  static Future<bool> canAutoInput() async {
    try {
      final hasPermission = await platform.invokeMethod('checkAccessibilityPermission');
      return hasPermission == true;
    } catch (e) {
      debugPrint('❌ 检查权限失败: $e');
      return false;
    }
  }
  
  /// 将文本复制到剪贴板（作为降级方案）
  static Future<void> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      debugPrint('❌ 复制失败: $e');
    }
  }
}
