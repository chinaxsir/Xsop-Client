// 文件位置: lib/api/api_client.dart

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _tokenKey = 'flarum_token';
  static const String _userIdKey = 'flarum_user_id';

  final Dio _dio;
  final String baseUrl;

  ApiClient({this.baseUrl = 'https://xsop.de'}) : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Token $token';
        }
        handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await logout();
        }
        handler.next(e);
      }
    ));
  }

  Future<Map<String, dynamic>> getForumInfo() async {
    final response = await _dio.get('/api');
    return _asMap(response.data);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  Future<Map<String, dynamic>> login(String identification, String password) async {
    final response = await _dio.post('/api/token', data: {
      'identification': identification,
      'password': password,
      'lifetime': 31536000, 
      'remember': true, 
    });
    final data = _asMap(response.data);
    final token = data['token'] as String?;
    final userId = data['userId'] as int?;
    if (token != null && token.isNotEmpty) {
      await _saveAuth(token, userId);
    }
    return data;
  }

  Future<Map<String, dynamic>> getDiscussions({int page = 1, int pageSize = 20, String? tag, String? author, String? sort}) async {
    final query = <String, dynamic>{'page[number]': page, 'page[size]': pageSize};
    if (tag != null && tag.isNotEmpty) query['filter[tag]'] = tag.trim();
    List<String> searchQueries = [];
    if (author != null && author.isNotEmpty) searchQueries.add('author:${author.trim()}');
    if (searchQueries.isNotEmpty) query['filter[q]'] = searchQueries.join(' ');
    if (sort != null) query['sort'] = sort;

    final response = await _dio.get('/api/discussions', queryParameters: query);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getDiscussion(int id, {int page = 1, int pageSize = 20}) async {
    final response = await _dio.get('/api/discussions/$id', queryParameters: {'page[number]': page, 'page[size]': pageSize, 'include': 'user,posts,posts.user'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getTags() async {
    final response = await _dio.get('/api/tags', queryParameters: {'include': 'parent'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getUser(int id) async {
    final response = await _dio.get('/api/users/$id', queryParameters: {'include': 'groups'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createDiscussion({required String title, required String content, List<String>? tagIds}) async {
    final Map<String, dynamic> relationships = {};
    if (tagIds != null && tagIds.isNotEmpty) {
      relationships["tags"] = {"data": tagIds.map((id) => {"type": "tags", "id": id}).toList()};
    }
    final Map<String, dynamic> payloadData = {"type": "discussions", "attributes": {"title": title, "content": content}};
    if (relationships.isNotEmpty) payloadData["relationships"] = relationships;
    final response = await _dio.post('/api/discussions', data: {"data": payloadData});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createPost(int discussionId, String content) async {
    final data = {"data": {"type": "posts", "attributes": {"content": content}, "relationships": {"discussion": {"data": {"type": "discussions", "id": discussionId.toString()}}}}};
    final response = await _dio.post('/api/posts', data: data);
    return _asMap(response.data);
  }

  Future<void> deletePost(int postId) async {
    await _dio.delete('/api/posts/$postId');
  }

  Future<void> editPost(int postId, String content) async {
    await _dio.patch('/api/posts/$postId', data: {
      "data": {"type": "posts", "id": postId.toString(), "attributes": {"content": content}}
    });
  }

  Future<void> warnUser(int userId, {int? postId, int strikes = 0, String? publicComment, String? privateComment}) async {
    final Map<String, dynamic> data = {
      "data": {"type": "warnings", "attributes": {"strikes": strikes, "publicComment": publicComment ?? "", "privateComment": privateComment ?? ""}, "relationships": {"user": {"data": {"type": "users", "id": userId.toString()}}}}
    };
    if (postId != null) data["data"]["relationships"]["post"] = {"data": {"type": "posts", "id": postId.toString()}};
    await _dio.post('/api/warnings', data: data);
  }

  String _extractErrorCode(dynamic data) {
    try {
      if (data is Map && data['errors'] is List && data['errors'].isNotEmpty) {
        return data['errors'][0]['code']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  // [终极探测引擎：支持独立 payNodeId 嗅探与 Action 后缀]
  Future<void> buyPost(int postId, int discussionId, String? payNodeId) async {
    DioException? lastErr;
    
    final endpoints = [
      // 1. 独立购买节点精准打击 (解决 not_found 的核心)
      if (payNodeId != null) '/api/pay-to-read/$payNodeId/purchase',
      if (payNodeId != null) '/api/paytoread/$payNodeId/purchase',
      if (payNodeId != null) '/api/pay-to-see/$payNodeId/purchase',
      if (payNodeId != null) '/api/pay-to-read/$payNodeId/buy',
      if (payNodeId != null) '/api/paytoread/$payNodeId/buy',
      if (payNodeId != null) '/api/pay-to-read/$payNodeId',
      if (payNodeId != null) '/api/paytoread/$payNodeId',
      
      // 2. Ziiven Pay To Read (主题级流派)
      '/api/pay-to-read/$discussionId/purchase',
      '/api/paytoread/$discussionId/purchase',
      '/api/pay-to-read/$discussionId/buy',
      '/api/paytoread/$discussionId/buy',
      '/api/discussions/$discussionId/pay-to-read',
      '/api/discussions/$discussionId/paytoread',

      // 3. Xypp Pay To See (单帖级流派)
      '/api/pay-to-see/$postId/purchase',
      '/api/pay-to-see/$postId/buy',
      '/api/posts/$postId/pay-to-see',

      // 4. 通用兜底
      '/api/pay-to-read/$discussionId',
      '/api/paytoread/$discussionId',
      '/api/pay-to-see/$postId',
      '/api/discussions/$discussionId/pay',
      '/api/posts/$postId/pay',
    ];

    // 包裹兼容 Flarum JSON API 的所有可能性
    final payloads = [
      {"data": {}},
      {"data": {"type": "paytoread", "attributes": {}}},
      {"data": {"type": "posts", "id": postId.toString()}},
      {"data": {"type": "discussions", "id": discussionId.toString()}},
    ];

    for (final ep in endpoints) {
      bool routeExists = false;
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return; // 秒扣款成功！
        } on DioException catch (e) {
          lastErr = e;
          final code = e.response?.statusCode;
          final errCode = _extractErrorCode(e.response?.data);

          // 遇到路由不存在，或指定的 ID 找不着模型，立刻短路跳过当前端点，换下一个 URL 测！
          if (code == 404 || code == 405 || errCode == 'route_not_found' || errCode == 'not_found') {
             routeExists = false;
             break; 
          }

          routeExists = true;
          final resStr = e.response?.data?.toString() ?? '';

          // 抓到余额不足等核心业务错误，说明接口完全通了，立刻抛给用户！
          if (resStr.contains('不足') || resStr.contains('enough') || resStr.contains('余额') || resStr.contains('fund') || code == 403) {
             throw e;
          }
        }
      }
      
      // 如果这个路由是通的（比如是 422 格式错误或 500），且所有 payload 都不行，把这个最真实的错误保留抛出
      if (routeExists && lastErr != null) {
        throw lastErr;
      }
    }
    
    // 把查找到的 PayNodeId 附在报错上，方便我们一眼看穿！
    throw Exception('API_ROUTE_UNMATCHED_PAYNODE_${payNodeId ?? "NULL"}');
  }

  Future<void> tipPost(int postId, int amount) async {
    DioException? lastErr;
    final endpoints = [
      '/api/posts/$postId/tip', 
      '/api/posts/$postId/reward', 
      '/api/tips',
      '/api/rewards',
    ];
    
    final payloads = [
      {"data": {"type": "tips", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
      {"data": {"attributes": {"amount": amount}}},
      {"amount": amount},
    ];

    for (final ep in endpoints) {
      bool routeExists = false;
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return;
        } on DioException catch (e) {
          lastErr = e;
          final code = e.response?.statusCode;
          final errCode = _extractErrorCode(e.response?.data);
          
          if (code == 404 || code == 405 || errCode == 'route_not_found' || errCode == 'not_found') {
             routeExists = false;
             break; 
          }
          routeExists = true;
        }
      }
      if (routeExists && lastErr != null) throw lastErr;
    }
    
    throw Exception('API_ROUTE_UNMATCHED');
  }

  Future<void> reportPost(int postId, String reason, String? detail) async {
    await _dio.post('/api/flags', data: {
      "data": {"type": "flags", "attributes": {"reason": reason, "reasonDetail": detail ?? ""}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}
    });
  }

  Future<void> likePost(int postId, bool isLiked) async {
    await _dio.patch('/api/posts/$postId', data: {"data": {"type": "posts", "id": postId.toString(), "attributes": {"isLiked": isLiked}}});
  }

  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _dio.get('/api/notifications', queryParameters: {'include': 'fromUser,subject'});
    return _asMap(response.data);
  }

  Future<Map<String, String>?> uploadFile(String filePath, {String? filename}) async {
    String name = filename ?? filePath.split('/').last;
    final formData = FormData.fromMap({
      'files[]': await MultipartFile.fromFile(filePath, filename: name),
    });
    
    final response = await _dio.post('/api/fof/upload', data: formData);
    final data = _asMap(response.data);
    final files = data['data'] as List<dynamic>?;
    if (files != null && files.isNotEmpty) {
       final attrs = files.first['attributes'] as Map<String, dynamic>?;
       if (attrs != null) return {'url': attrs['url']?.toString() ?? '', 'baseName': attrs['baseName']?.toString() ?? name};
    }
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
  }

  Future<bool> get isLoggedIn async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, dynamic>> getDynamicList(String endpoint, {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get(endpoint, queryParameters: queryParameters);
    return _asMap(response.data);
  }

  Future<void> _saveAuth(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (userId != null) await prefs.setInt(_userIdKey, userId);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
