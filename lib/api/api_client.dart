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

  // [极速重构：砍掉冗余盲测，直击靶心，实现毫秒级响应]
  Future<void> buyPost(int postId, int discussionId) async {
    DioException? lastErr;
    
    // 按国内 Flarum 站长的使用习惯与流行度对路由进行优先级排序
    final endpoints = [
      '/api/pay-to-read/$postId',                 // 热门：付费阅读 (单帖)
      '/api/pay-to-read/$discussionId',           // 热门：付费阅读 (主题)
      '/api/pay-to-see/$postId',                  // 经典：付费可见 (单帖)
      '/api/pay-to-see/$discussionId',            // 经典：付费可见 (主题)
      '/api/posts/$postId/pay-to-read',
      '/api/discussions/$discussionId/pay-to-read',
      '/api/posts/$postId/pay',
      '/api/discussions/$discussionId/pay',
      '/api/posts/$postId/purchase',
      '/api/posts/$postId/buy',
    ];
    
    // 舍弃笨重的多重 Payload 组合，统一使用 Flarum 官方 action 通用规范，避免引发额外格式验证错误
    final payload = {"data": {}};

    for (final ep in endpoints) {
      try {
        await _dio.post(ep, data: payload);
        return; // 秒扣款成功！
      } on DioException catch (e) {
        lastErr = e;
        final code = e.response?.statusCode;
        final resStr = e.response?.data?.toString() ?? '';

        // [拦截器防御]：如果返回 404 (没这个路由) 或 405 (不支持POST)，立刻极速跳过，不浪费一毫秒
        if (code == 404 || code == 405 || resStr.contains('not_found')) {
           continue; 
        }

        // 如果服务器返回了 422 且包含余额不足、没有足够资金等字样，说明路由撞对了！立刻阻断并抛出！
        if (resStr.contains('不足') || 
            resStr.contains('not enough') || 
            resStr.contains('余额') || 
            resStr.contains('fund') || 
            resStr.contains('insufficient') || 
            code == 403) {
           throw e;
        }
        
        // 其他情况 (比如 500)，大概率也是撞对路由了但插件内部出错，抛出真实原因
        throw e;
      }
    }
    
    if (lastErr != null) throw lastErr;
    throw Exception('购买被阻断：未能匹配到正确的付费路由，请检查后端插件是否开启 API 支持。');
  }

  // [打赏接口同步进行极速减负优化]
  Future<void> tipPost(int postId, int amount) async {
    DioException? lastErr;
    final endpoints = [
      '/api/posts/$postId/tip', 
      '/api/posts/$postId/reward', 
      '/api/tips',
      '/api/rewards',
    ];
    
    // 保留打赏必备的属性格式，其他全砍
    final payloads = [
      {"data": {"type": "tips", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
      {"data": {"attributes": {"amount": amount}}},
      {"amount": amount},
    ];

    for (final ep in endpoints) {
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return;
        } on DioException catch (e) {
          lastErr = e;
          final code = e.response?.statusCode;
          if (code == 404 || code == 405) break; 
        }
      }
    }
    if (lastErr != null) throw lastErr;
    throw Exception('打赏操作被阻断：未匹配到有效的 API 接口。');
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
