import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AI 助手角色类型
enum AIRole {
  chat,          // 闲聊
  salesAssistant, // 销售助手
  nutritionist;   // 营养师
  
  /// 获取角色的显示名称
  String get displayName {
    switch (this) {
      case AIRole.chat:
        return '闲聊';
      case AIRole.salesAssistant:
        return '销售助手';
      case AIRole.nutritionist:
        return '营养师';
    }
  }
  
  /// 获取角色的系统提示词
  String get systemPrompt {
    switch (this) {
      case AIRole.chat:
        return '你是一个友好、幽默的聊天伙伴。你善于倾听，能够理解对方的情绪，给予温暖和积极的回应。你的回复要自然、轻松、有趣，让对话充满活力。';
      case AIRole.salesAssistant:
        return '你是一个专业的销售助手，擅长分析客户消息并生成恰当的回复。你的回复要简洁、专业、友好，能够准确把握客户需求，提供有价值的建议。';
      case AIRole.nutritionist:
        return '你是一位专业的营养师，精通营养学和健康饮食知识。你善于根据客户的需求提供科学、实用的营养建议，帮助客户养成健康的饮食习惯。你的回复要专业、详细、易懂。';
    }
  }
  
  /// 获取角色图标
  String get icon {
    switch (this) {
      case AIRole.chat:
        return '💬';
      case AIRole.salesAssistant:
        return '💼';
      case AIRole.nutritionist:
        return '🥗';
    }
  }
}

class AIService {
  static const String _baseUrl = 'https://ark.cn-beijing.volces.com/api/v3/chat/completions';
  static const String _apiKey = '';
  static const String _endpointId = 'doubao-seed-1-6-251015';

  /// 发送文本到大模型并获取响应
  /// 
  /// [userPrompt] 用户输入的文本或系统构建的提示词
  /// [role] AI 助手角色类型,默认为销售助手
  /// [useDirectPrompt] 是否直接使用提示词（不添加额外前缀）
  /// 返回大模型生成的响应内容
  Future<String> sendTextToAI(
    String userPrompt, {
    AIRole role = AIRole.salesAssistant,
    bool useDirectPrompt = true,
  }) async {
    try {
      // 构建完整的提示词
      final String fullPrompt = useDirectPrompt 
          ? userPrompt 
          : "我的提示词是：$userPrompt";

      // 构建请求体
      final Map<String, dynamic> requestBody = {
        'model': _endpointId,
        'messages': [
          {
            'role': 'system',
            'content': role.systemPrompt,
          },
          {
            'role': 'user',
            'content': fullPrompt,
          }
        ],
        'temperature': 0.7, // 控制创造性，0.7 比较平衡
        'max_tokens': 400,  // 限制回复长度
      };

      // 发送 POST 请求
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('请求超时，请检查网络连接');
        },
      );

      // 检查响应状态
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        // 解析大模型返回的内容
        if (responseData.containsKey('choices') && 
            responseData['choices'] is List && 
            responseData['choices'].isNotEmpty) {
          final String aiResponse = responseData['choices'][0]['message']['content'];
          return aiResponse.trim();
        } else {
          throw Exception('响应格式异常：未找到有效的回复内容');
        }
      } else {
        final errorBody = response.body;
        debugPrint('❌ API 错误: $errorBody');
        throw Exception('请求失败，状态码：${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ AI 调用失败: $e');
      throw Exception('AI 服务调用失败：$e');
    }
  }
  
  /// 专门用于分析微信聊天内容并生成回复的方法
  /// 
  /// [ocrText] OCR 识别出的聊天文本
  /// [role] AI 助手角色类型
  /// 返回适合回复的文本
  Future<String> generateWeChatReply(String ocrText, {AIRole role = AIRole.salesAssistant}) async {
    final prompt = _buildWeChatPrompt(ocrText, role);
    return await sendTextToAI(prompt, role: role, useDirectPrompt: true);
  }
  
  /// 构建微信聊天场景的提示词
  String _buildWeChatPrompt(String ocrText, AIRole role) {
    String taskRequirement;
    
    switch (role) {
      case AIRole.chat:
        taskRequirement = '''任务要求：
          1. 从上述文本是一组微信对话，有2个角色，一个是“我”，一个是“对方”；
          2. 你需要帮“我”给“对方”回复一句话，回复要像个真人；
          3. 回复务必要贴近聊天的内容，不要跑题；没有话题时，可以适当引入新的话题。
          4. 回复参考“我”之前回复的字数、语气和风格；
          5. 理解对方的情绪和话题；
          6. 注意，你的角色是“我”，是从“我”的角度进行回复，不是从“对方”的角度回复；

          回复要求：
          - 字数：20-60字之内
          - 内容：贴近对方的话题，适当展现幽默感
          - 格式：直接给出回复内容，不要添加"回复："等前缀
          - 如果无法识别对方消息，回复"哈哈，没听清楚，再说一遍？"''';
        break;
        
      case AIRole.salesAssistant:
        taskRequirement = '''任务要求：
          1. 从上述文本是一组微信对话，有2个角色，一个是“我”，一个是“对方”；
          2. 你需要帮“我”给“对方”回复一句话，回复要像个真人；
          3. 回复务必要贴近聊天的内容，不要跑题，你是个销售员，你的任务是把握销售机会，促进成交。
          4. 你销售的产品是**公司的减肥产品脂20，主要卖点是安全有效、无副作用、科学健康;在合适的时机再销售产品，不合适时不要强行推销。
          5. 回复参考“我”之前回复的字数、语气和风格；
          6. 理解对方的情绪和话题；
          7. 注意，你的角色是“我”，是从“我”的角度进行回复，不是从“对方”的角度回复；

          回复要求：
          - 字数：20-60字之内
          - 内容：贴近对方的话题，适当展现幽默感
          - 格式：直接给出回复内容，不要添加"回复："等前缀
          - 如果无法识别对方消息，回复"哈哈，没听清楚，再说一遍？"''';
        break;
        
      case AIRole.nutritionist:
        taskRequirement = '''任务要求：
          1. 从上述文本是一组微信对话，有2个角色，一个是“我”，一个是“对方”；
          2. 你需要帮“我”给“对方”回复一句话，回复要像个真人；
          3. 回复务必要贴近聊天的内容，不要跑题，你是个营养师，你的任务是提供科学的营养建议和健康指导；
          4. 如果用户聊跟营养健康无关的话题，可以适当引导回营养健康相关的话题；
          5. 回复参考“我”之前回复的字数、语气和风格；
          6. 理解对方的情绪和话题；
          7. 注意，你的角色是“我”，是从“我”的角度进行回复，不是从“对方”的角度回复；

          回复要求：
          - 字数：20-60字之内
          - 内容：贴近对方的话题，要展现自己的专业性
          - 格式：直接给出回复内容，不要添加"回复："等前缀
          - 如果无法识别对方消息，回复"哈哈，没听清楚，再说一遍？"''';
        break;
    }
    
    return '''你是一个${role.displayName}。以下是从微信聊天界面OCR识别出的文本内容：

$ocrText

$taskRequirement
    - 内容：针对客户的具体问题或需求
    - 格式：直接给出回复内容，不要添加"回复："等前缀
    - 如果无法识别客户消息，回复"不好意思，能再说一遍吗？"

    请直接输出回复内容：''';
  }
}
