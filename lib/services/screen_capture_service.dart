import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Canvas, Offset, Paint;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenCaptureService {
  static final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  static bool _isProcessing = false;
  
  /// 截图并通过 OCR 识别文本
  static Future<String> captureAndRecognize() async {
    // 防止重复处理
    if (_isProcessing) {
      debugPrint('⚠️ 正在处理中，忽略重复请求');
      return '';
    }
    
    _isProcessing = true;
    debugPrint('🔍 ========== ScreenCaptureService 开始执行 ==========');
    debugPrint('📸 [步骤1/5] 准备截图...');
    print('🔍 ========== ScreenCaptureService 开始执行 ==========');
    print('📸 准备截图并识别文字...');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 0. 清除旧的截图数据,确保不会读取到上次的截图
      debugPrint('🧹 [步骤0/5] 清除旧截图数据...');
      await prefs.remove('screenshot_ready');
      await prefs.remove('last_screenshot_path');
      await prefs.remove('screenshot_error');
      await prefs.remove('screenshot_response_time_str');
      await prefs.remove('screenshot_response_time');
      
      // 强制刷新，确保清除生效
      await prefs.reload();
      debugPrint('   ✓ 旧数据已清除并重新加载');
      
      // 1. 通过 SharedPreferences 发送截图请求
      debugPrint('📸 [步骤2/5] 发送截图请求到无障碍服务...');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('screenshot_request_time', timestamp);
      debugPrint('   ✓ 请求时间戳: $timestamp');
      
      final success = await prefs.setBool('screenshot_requested', true);
      debugPrint('   ✓ SharedPreferences 写入: ${success ? "成功" : "失败"}');
      
      // 验证是否写入成功
      final readBack = prefs.getBool('screenshot_requested');
      debugPrint('   ✓ 验证读取: screenshot_requested = $readBack');
      
      // 2. 等待截图完成 - 使用轮询机制
      debugPrint('⏳ [步骤3/5] 轮询等待截图生成（最多2秒）...');
      
      bool screenshotReady = false;
      String? screenshotPath;
      final maxAttempts = 40; // 最多等待2秒 (40 * 50ms)
      final checkInterval = 50; // 每50ms检查一次，更快响应
      
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (attempt > 0) { // 第一次不延迟，立即检查
          await Future.delayed(Duration(milliseconds: checkInterval));
        }
        
        // 每次检查前重新加载 SharedPreferences，确保获取最新数据
        await prefs.reload();
        
        screenshotReady = prefs.getBool('screenshot_ready') ?? false;
        screenshotPath = prefs.getString('last_screenshot_path');
        
        // 读取响应时间
        int screenshotTime = 0;
        final timeStr = prefs.getString('screenshot_response_time_str');
        if (timeStr != null && timeStr.isNotEmpty) {
          screenshotTime = int.tryParse(timeStr) ?? 0;
        } else {
          screenshotTime = prefs.getInt('screenshot_response_time') ?? 0;
        }
        
        // 检查是否是当前请求的截图（时间戳匹配）
        if (screenshotReady && screenshotPath != null && screenshotPath.isNotEmpty) {
          // 确保截图响应时间晚于请求时间
          if (screenshotTime >= timestamp) {
            debugPrint('   ✓ 在第 ${attempt + 1} 次检查时获取到新截图');
            break;
          } else {
            screenshotReady = false; // 旧截图，继续等待
          }
        }
      }
      
      // 3. 验证截图是否成功获取
      debugPrint('📂 [步骤4/5] 验证截图结果...');
      
      if (!screenshotReady || screenshotPath == null || screenshotPath.isEmpty) {
        final error = prefs.getString('screenshot_error') ?? '超时或截图失败';
        debugPrint('❌ 截图失败: $error');
        debugPrint('🔍 ========== ScreenCaptureService 失败结束 ==========');
        _isProcessing = false;
        return '';
      }
      
      debugPrint('✅ 截图成功: $screenshotPath');
      
      // 4. 检查文件是否存在
      debugPrint('📁 [步骤5/5] 验证截图文件...');
      final screenshotFile = File(screenshotPath);
      final exists = await screenshotFile.exists();
      debugPrint('   ✓ 文件存在: $exists');
      
      if (!exists) {
        debugPrint('❌ 截图文件不存在: $screenshotPath');
        debugPrint('🔍 ========== ScreenCaptureService 失败结束 ==========');
        _isProcessing = false;
        return '';
      }
      
      final fileSize = await screenshotFile.length();
      debugPrint('   ✓ 文件大小: ${(fileSize / 1024).toStringAsFixed(2)} KB');
      
      // 5. 裁剪图片，去除顶部状态栏和标题栏区域
      debugPrint('✂️ [图片裁剪] 开始裁剪顶部区域...');
      final croppedImagePath = await _cropTopArea(screenshotFile);
      final imagePath = croppedImagePath ?? screenshotPath;
      
      if (croppedImagePath != null) {
        final croppedSize = await File(croppedImagePath).length();
        debugPrint('   ✓ 裁剪完成: ${(croppedSize / 1024).toStringAsFixed(2)} KB');
      } else {
        debugPrint('   ⚠️ 裁剪失败，使用原始图片');
      }
      
      // 6. 使用 Google ML Kit 进行 OCR 识别
      debugPrint('🔍 [OCR识别] 开始文字识别...');
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      // 7. 提取识别的文本
      final String text = recognizedText.text;
      
      print('✅ OCR识别完成: ${text.length} 字符, ${recognizedText.blocks.length} 文本块');
      
      // 8. 格式化对话内容（基于颜色识别）
      final formattedText = await _formatChatMessages(recognizedText, File(imagePath));
      
      if (formattedText.isNotEmpty) {
        print('💬 格式化后的对话内容:\n$formattedText\n');
      }
      
      // 9. 清除状态
      await prefs.setBool('screenshot_ready', false);
      await prefs.setBool('screenshot_requested', false);
      
      // 10. 清理裁剪的临时文件
      if (croppedImagePath != null) {
        try {
          await File(croppedImagePath).delete();
        } catch (e) {
          debugPrint('⚠️ 删除临时文件失败: $e');
        }
      };
      
      debugPrint('🔍 ========== ScreenCaptureService 成功结束 ==========\n');
      _isProcessing = false;
      
      // 返回格式化后的文本（如果有），否则返回原始文本
      return formattedText.isNotEmpty ? formattedText : text;
      
    } catch (e, stackTrace) {
      debugPrint('❌ 截图或 OCR 识别异常: $e');
      debugPrint('📋 堆栈: $stackTrace');
      debugPrint('🔍 ========== ScreenCaptureService 异常结束 ==========\n');
      _isProcessing = false;
      return '';
    }
  }
  
  /// 格式化聊天消息（基于底色识别对方和自己）
  static Future<String> _formatChatMessages(RecognizedText recognizedText, File screenshotFile) async {
    try {
      if (recognizedText.blocks.isEmpty) {
        return '';
      }
      
      // 加载图片用于颜色检测
      final imageBytes = await screenshotFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      final screenWidth = image.width.toDouble();
      
      // 按 Y 坐标排序（从上到下）
      final sortedBlocks = recognizedText.blocks.toList()
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      
      // 过滤掉系统消息
      final filteredBlocks = sortedBlocks.where((block) {
        final text = block.text.trim();
        return text.isNotEmpty && !_isSystemMessage(text);
      }).toList();
      
      if (filteredBlocks.isEmpty) {
        image.dispose();
        return '';
      }
      
      // 提取每个文本块的背景颜色
      List<Map<String, dynamic>> colors = [];
      for (var block in filteredBlocks) {
        final color = await _extractBackgroundColor(image, block.boundingBox);
        colors.add(color);
      }
      
      debugPrint('🎨 开始颜色分析，共 ${colors.length} 个文本块');
      for (int i = 0; i < colors.length; i++) {
        final c = colors[i];
        final block = filteredBlocks[i];
        final text = block.text.replaceAll('\n', ' ').trim();
        final shortText = text.length > 15 ? '${text.substring(0, 15)}...' : text;
        debugPrint('   文本块 $i: "$shortText" RGB(${c['r']}, ${c['g']}, ${c['b']})');
      }
      
      // 将颜色聚类成2组
      final clusters = _clusterColors(colors);
      
      // 判断哪一组是"我"
      // 优先使用颜色特征：白色底（对方）vs 绿色底（我）
      
      // 计算每组的平均颜色和位置
      int group0RedSum = 0, group0GreenSum = 0, group0BlueSum = 0, group0Count = 0, group0RightCount = 0;
      int group1RedSum = 0, group1GreenSum = 0, group1BlueSum = 0, group1Count = 0, group1RightCount = 0;
      
      for (int i = 0; i < filteredBlocks.length; i++) {
        final block = filteredBlocks[i];
        final isRight = block.boundingBox.right > screenWidth * 0.6;
        
        if (clusters[i] == 0) {
          group0RedSum += colors[i]['r'] as int;
          group0GreenSum += colors[i]['g'] as int;
          group0BlueSum += colors[i]['b'] as int;
          group0Count++;
          if (isRight) group0RightCount++;
        } else {
          group1RedSum += colors[i]['r'] as int;
          group1GreenSum += colors[i]['g'] as int;
          group1BlueSum += colors[i]['b'] as int;
          group1Count++;
          if (isRight) group1RightCount++;
        }
      }
      
      final group0AvgRed = group0Count > 0 ? group0RedSum / group0Count : 0;
      final group0AvgGreen = group0Count > 0 ? group0GreenSum / group0Count : 0;
      final group0AvgBlue = group0Count > 0 ? group0BlueSum / group0Count : 0;
      
      final group1AvgRed = group1Count > 0 ? group1RedSum / group1Count : 0;
      final group1AvgGreen = group1Count > 0 ? group1GreenSum / group1Count : 0;
      final group1AvgBlue = group1Count > 0 ? group1BlueSum / group1Count : 0;
      
      debugPrint('📊 颜色分组结果:');
      debugPrint('   组0: 数量=$group0Count, 平均RGB(${group0AvgRed.toInt()}, ${group0AvgGreen.toInt()}, ${group0AvgBlue.toInt()}), 右侧=$group0RightCount');
      debugPrint('   组1: 数量=$group1Count, 平均RGB(${group1AvgRed.toInt()}, ${group1AvgGreen.toInt()}, ${group1AvgBlue.toInt()}), 右侧=$group1RightCount');
      
      // 判断哪组是白色底（对方），哪组是绿色底（我）
      // 白色特征: R≈G≈B，且数值较高 (>200)
      // 绿色特征: G > R 且 G > B
      
      final group0IsWhite = _isWhiteBackground(group0AvgRed.toDouble(), group0AvgGreen.toDouble(), group0AvgBlue.toDouble());
      final group1IsWhite = _isWhiteBackground(group1AvgRed.toDouble(), group1AvgGreen.toDouble(), group1AvgBlue.toDouble());
      
      final group0IsGreen = _isGreenBackground(group0AvgRed.toDouble(), group0AvgGreen.toDouble(), group0AvgBlue.toDouble());
      final group1IsGreen = _isGreenBackground(group1AvgRed.toDouble(), group1AvgGreen.toDouble(), group1AvgBlue.toDouble());
      
      debugPrint('   组0: 白色=$group0IsWhite, 绿色=$group0IsGreen');
      debugPrint('   组1: 白色=$group1IsWhite, 绿色=$group1IsGreen');
      
      // 判断"我"是哪一组
      int myGroup;
      
      if (group0IsGreen && group1IsWhite) {
        // 组0是绿色，组1是白色 -> 组0是"我"
        myGroup = 0;
        debugPrint('✅ 根据颜色判断: 组0(绿色)是"我"，组1(白色)是"对方"');
      } else if (group1IsGreen && group0IsWhite) {
        // 组1是绿色，组0是白色 -> 组1是"我"
        myGroup = 1;
        debugPrint('✅ 根据颜色判断: 组1(绿色)是"我"，组0(白色)是"对方"');
      } else {
        // 颜色特征不明显，使用位置判断（右侧的是"我"）
        myGroup = group0RightCount > group1RightCount ? 0 : 1;
        debugPrint('⚠️ 颜色特征不明显，使用位置判断: ${myGroup == 0 ? "组0" : "组1"}(右侧)是"我"');
      }
      
      // 基于颜色分组生成对话
      List<String> formattedMessages = [];
      
      for (var i = 0; i < filteredBlocks.length; i++) {
        final block = filteredBlocks[i];
        final text = block.text.trim();
        final speaker = clusters[i] == myGroup ? "我" : "对方";
        
        // 给每个文本块加句号（如果没有标点符号结尾）
        final textWithPunctuation = _addPunctuationIfNeeded(text);
        
        // 合并逻辑：如果和上一条是同一个人，追加；否则新起一条
        if (formattedMessages.isNotEmpty) {
          final lastMessage = formattedMessages.last;
          final lastSpeaker = lastMessage.split('：')[0];
          
          if (lastSpeaker == speaker) {
            // 同一个人，追加文本
            formattedMessages[formattedMessages.length - 1] = lastMessage + textWithPunctuation;
          } else {
            // 不同人，新起一条
            formattedMessages.add('$speaker：$textWithPunctuation');
          }
        } else {
          // 第一条消息
          formattedMessages.add('$speaker：$textWithPunctuation');
        }
      }
      
      image.dispose();
      return formattedMessages.join('\n');
      
    } catch (e) {
      debugPrint('❌ 格式化消息失败: $e');
      return '';
    }
  }
  
  /// 将属于同一条消息的多个 TextBlock 分组
  /// 判断依据：垂直距离很近、左边界或右边界对齐
  static List<List<TextBlock>> _groupMessageBlocks(List<TextBlock> blocks, double screenWidth) {
    if (blocks.isEmpty) return [];
    
    List<List<TextBlock>> groups = [];
    List<TextBlock> currentGroup = [blocks[0]];
    
    for (int i = 1; i < blocks.length; i++) {
      final prevBlock = blocks[i - 1];
      final currBlock = blocks[i];
      
      // 计算垂直距离
      final verticalGap = currBlock.boundingBox.top - prevBlock.boundingBox.bottom;
      
      // 计算左边界和右边界的差异
      final leftDiff = (currBlock.boundingBox.left - prevBlock.boundingBox.left).abs();
      final rightDiff = (currBlock.boundingBox.right - prevBlock.boundingBox.right).abs();
      
      final isLeftAligned = leftDiff < 30;
      final isRightAligned = rightDiff < 30;
      
      // 检测是否跨越屏幕中线（从左侧消息跨到右侧消息）
      final prevIsLeft = prevBlock.boundingBox.left < screenWidth * 0.4;
      final currIsRight = currBlock.boundingBox.right > screenWidth * 0.6;
      final crossesMidline = prevIsLeft && currIsRight;
      
      final isSameMessage = verticalGap < 50 && (isLeftAligned || isRightAligned) && !crossesMidline;
      
      if (isSameMessage) {
        currentGroup.add(currBlock);
      } else {
        groups.add(currentGroup);
        currentGroup = [currBlock];
      }
    }
    
    // 添加最后一组
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }
    
    return groups;
  }
  
  /// 给文本添加标点符号（如果需要）
  /// 如果文本已经有标点符号结尾，则不添加
  static String _addPunctuationIfNeeded(String text) {
    if (text.isEmpty) return text;
    
    // 检查是否已经有标点符号结尾
    final lastChar = text[text.length - 1];
    final punctuations = ['。', '！', '？', '，', '、', '.', '!', '?', ',', '~', '…'];
    
    if (punctuations.contains(lastChar)) {
      return text; // 已经有标点，不添加
    }
    
    return '$text。'; // 添加句号
  }
  
  /// 判断是否是系统消息（时间、通话记录等）
  static bool _isSystemMessage(String text) {
    // 过滤时间戳
    if (RegExp(r'^\d{1,2}月\d{1,2}日').hasMatch(text)) return true;
    if (RegExp(r'上午|下午|晚上|周[一二三四五六日]').hasMatch(text) && text.length < 20) return true;
    
    // 过滤通话记录
    if (text.contains('通话时长')) return true;
    
    // 过滤顶部状态栏信息
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text)) return true; // 时间 11:45
    if (text.contains('5G') || text.contains('4G') || text.contains('KB/s')) return true;
    if (text.contains('%') && text.length < 10) return true; // 电量
    
    // 过滤返回按钮等
    if (text == '<' || text == '>' || text == '()' || text == '⬅' || text == 'く') return true;
    
    // 过滤联系人名称标题（通常在顶部）
    if (text.startsWith('同事') && text.length < 30) return true;
    
    // 过滤纯数字或数字+符号（可能是通知徽章等）
    if (RegExp(r'^[\d\s+]+$').hasMatch(text) && text.length < 10) return true;
    
    // 过滤单个字符或特殊符号
    if (text.length <= 2 && RegExp(r'^[^\u4e00-\u9fa5a-zA-Z0-9]').hasMatch(text)) return true;
    
    return false;
  }
  
  /// 合并连续的同一说话人的消息
  static List<String> _mergeConsecutiveMessages(List<String> messages) {
    if (messages.isEmpty) return [];
    
    List<String> merged = [];
    String? currentSpeaker;
    List<String> currentTexts = [];
    
    for (var message in messages) {
      final parts = message.split('：');
      if (parts.length < 2) continue;
      
      final speaker = parts[0];
      final text = parts.sublist(1).join('：');
      
      if (speaker == currentSpeaker) {
        currentTexts.add(text);
      } else {
        if (currentSpeaker != null && currentTexts.isNotEmpty) {
          merged.add('$currentSpeaker：${currentTexts.join('')}');
        }
        currentSpeaker = speaker;
        currentTexts = [text];
      }
    }
    
    // 添加最后一组
    if (currentSpeaker != null && currentTexts.isNotEmpty) {
      merged.add('$currentSpeaker：${currentTexts.join('')}');
    }
    
    return merged;
  }
  
  /// 释放资源
  static Future<void> dispose() async {
    await _textRecognizer.close();
  }
  
  /// 裁剪图片顶部区域（去除状态栏和标题栏）
  /// 返回裁剪后的临时文件路径，失败返回 null
  static Future<String?> _cropTopArea(File originalFile) async {
    try {
      // 读取原始图片
      final imageBytes = await originalFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      
      final width = image.width;
      final height = image.height;
      
      // 裁剪顶部区域：
      // 状态栏约占 60-100 像素（时间、网速、电池等）
      // 微信标题栏约占 100-150 像素（返回按钮、聊天对象名称、更多按钮）
      // 总共裁剪顶部 15% 的高度（大约 150-200 像素）
      final cropTopPercent = 0.15; // 裁剪顶部 15%
      final cropTop = (height * cropTopPercent).toInt();
      final newHeight = height - cropTop;
      
      debugPrint('   📐 原始尺寸: ${width}x${height}, 裁剪顶部: ${cropTop}px, 新尺寸: ${width}x${newHeight}');
      
      // 获取图片数据
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        return null;
      }
      
      final buffer = byteData.buffer.asUint8List();
      
      // 创建新的图片数据（裁剪后）
      final croppedBuffer = Uint8List(width * newHeight * 4);
      
      for (int y = 0; y < newHeight; y++) {
        final srcOffset = ((y + cropTop) * width) * 4;
        final dstOffset = (y * width) * 4;
        croppedBuffer.setRange(
          dstOffset,
          dstOffset + width * 4,
          buffer,
          srcOffset,
        );
      }
      
      // 编码为PNG
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        croppedBuffer,
        width,
        newHeight,
        ui.PixelFormat.rgba8888,
        (result) {
          completer.complete(result);
        },
      );
      
      final croppedImage = await completer.future;
      canvas.drawImage(croppedImage, Offset.zero, Paint());
      
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(width, newHeight);
      final pngBytes = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      
      // 清理资源
      image.dispose();
      croppedImage.dispose();
      finalImage.dispose();
      
      if (pngBytes == null) {
        return null;
      }
      
      // 保存到临时文件
      final tempDir = originalFile.parent;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final croppedPath = '${tempDir.path}/cropped_$timestamp.png';
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(pngBytes.buffer.asUint8List());
      
      return croppedPath;
      
    } catch (e, stackTrace) {
      debugPrint('❌ 裁剪图片失败: $e');
      debugPrint('📋 堆栈: $stackTrace');
      return null;
    }
  }
  
  /// 判断是否是白色背景（对方的消息）
  /// 白色特征: R、G、B 都比较高且接近
  static bool _isWhiteBackground(double r, double g, double b) {
    // 白色：三个分量都比较高（通常>200）且差异小
    final minValue = min(min(r, g), b);
    final maxValue = max(max(r, g), b);
    final diff = maxValue - minValue;
    
    // 判断条件：
    // 1. 最小值要大于180（整体亮度高）
    // 2. 三个分量的差异要小于30（颜色接近灰度）
    return minValue > 180 && diff < 30;
  }
  
  /// 判断是否是绿色背景（我的消息）
  /// 绿色特征: G > R 且 G > B，且绿色分量明显
  static bool _isGreenBackground(double r, double g, double b) {
    // 微信绿色气泡特征：
    // 1. 绿色分量最高
    // 2. 绿色分量 > 红色分量 + 阈值（通常差值在15-50之间）
    // 3. 绿色分量要有一定强度（>150）
    
    final greenDominant = g > r && g > b;
    final greenStrength = g > 150;
    final greenDiff = g - r;
    
    // 判断条件：绿色占优势，且绿色比红色高出至少10个单位
    return greenDominant && greenStrength && greenDiff > 10;
  }
  
  /// 从图片中提取文本块的背景颜色
  /// 返回值：颜色的 RGB 平均值 (0-255)
  static Future<Map<String, dynamic>> _extractBackgroundColor(
    ui.Image image, 
    ui.Rect boundingBox,
  ) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return {'r': 255, 'g': 255, 'b': 255};
      
      final buffer = byteData.buffer.asUint8List();
      
      // 采样文本块的气泡背景色
      // 采样位置：文本块中心偏下方（避开文字，采到气泡底色）
      final sampleX = (boundingBox.left + boundingBox.width / 2).clamp(0, image.width - 1).toInt();
      final sampleY = (boundingBox.bottom - 5).clamp(0, image.height - 1).toInt();
      
      int r = 0, g = 0, b = 0;
      int count = 0;
      
      // 采样 6x6 区域（减少采样范围，提升速度）
      for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
          final x = (sampleX + dx).clamp(0, image.width - 1);
          final y = (sampleY + dy).clamp(0, image.height - 1);
          final offset = (y * image.width + x) * 4;
          
          if (offset + 2 < buffer.length) {
            r += buffer[offset];
            g += buffer[offset + 1];
            b += buffer[offset + 2];
            count++;
          }
        }
      }
      
      if (count == 0) return {'r': 255, 'g': 255, 'b': 255};
      
      return {
        'r': r ~/ count,
        'g': g ~/ count,
        'b': b ~/ count,
      };
    } catch (e) {
      debugPrint('⚠️ 提取颜色失败: $e');
      return {'r': 255, 'g': 255, 'b': 255};
    }
  }
  
  /// 计算两个颜色的相似度（欧氏距离）
  static double _colorDistance(Map<String, dynamic> c1, Map<String, dynamic> c2) {
    final dr = (c1['r'] - c2['r']).toDouble();
    final dg = (c1['g'] - c2['g']).toDouble();
    final db = (c1['b'] - c2['b']).toDouble();
    return sqrt(dr * dr + dg * dg + db * db);
  }
  
  /// 将颜色聚类成2组（对方 vs 我）
  /// 返回每个文本块属于哪一组 (0 或 1)
  /// 改进版：基于颜色语义进行聚类，而不是纯粹的距离
  static List<int> _clusterColors(List<Map<String, dynamic>> colors) {
    if (colors.length < 2) return List.filled(colors.length, 0);
    
    List<int> clusters = List.filled(colors.length, 0);
    
    // 方案：先对每个颜色进行语义分类（绿色、白色/灰色、其他）
    // 然后将绿色归为一组，白色/灰色归为另一组
    
    int greenCount = 0;
    int whiteGrayCount = 0;
    
    for (int i = 0; i < colors.length; i++) {
      final r = colors[i]['r'] as int;
      final g = colors[i]['g'] as int;
      final b = colors[i]['b'] as int;
      
      // 判断是否是绿色（微信绿色气泡）
      final isGreen = _isGreenBackground(r.toDouble(), g.toDouble(), b.toDouble());
      
      // 判断是否是白色/灰色（对方消息，包括浅灰色）
      // 白色/灰色特征：R≈G≈B（差异小），且不是深色
      final minValue = min(min(r, g), b);
      final maxValue = max(max(r, g), b);
      final diff = maxValue - minValue;
      final isWhiteGray = diff < 40 && minValue > 100; // 扩大灰色范围，包括RGB(173,173,173)
      
      if (isGreen) {
        clusters[i] = 1; // 绿色组
        greenCount++;
      } else if (isWhiteGray) {
        clusters[i] = 0; // 白色/灰色组
        whiteGrayCount++;
      } else {
        // 既不是明显的绿色，也不是明显的白色/灰色
        // 根据绿色倾向判断：G > (R+B)/2 则归为绿色组
        final greenTendency = g > (r + b) / 2;
        clusters[i] = greenTendency ? 1 : 0;
      }
    }
    
    debugPrint('🔍 颜色语义分类: 绿色=$greenCount, 白色/灰色=$whiteGrayCount');
    
    return clusters;
  }
}


