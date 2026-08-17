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
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
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

  // [新增核心修复：自动轮询探测 Flarum 付费阅读插件的扣款路由]
  Future<void> buyPost(int postId) async {
    final endpoints = [
      '/api/posts/$postId/pay', 
      '/api/posts/$postId/buy', 
      '/api/posts/$postId/purchase'
    ];
    
    for (final ep in endpoints) {
      try {
        await _dio.post(ep, data: {"data": {}});
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        // 如果是 422 余额不足，403 没权限，说明路由是对的，直接抛出异常
        if (code == 422 || code == 403 || code == 500) {
           throw e; 
        }
        // 如果 404 或 405，说明当前插件不是这个路由，继续试探下一个
        if (code == 404 || code == 405) {
           continue;
        }
      }
    }
    throw Exception('当前系统未安装适配的购买插件，或该接口已被隐藏。');
  }

  Future<void> tipPost(int postId, int amount) async {
    final endpoints = [
      '/api/posts/$postId/tip', 
      '/api/posts/$postId/reward', 
      '/api/tips',
      '/api/rewards',
      '/api/money-transfers'
    ];
    
    for (final ep in endpoints) {
      final payloads = [
        {"data": {"type": "tips", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
        {"data": {"type": "rewards", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
        {"data": {"type": "post_tips", "attributes": {"amount": amount}, "relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
        {"data": {"attributes": {"amount": amount}}},
        {"amount": amount},
        {"money": amount}
      ];
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 422 || code == 403 || code == 500) {
             throw e; 
          }
          if (code == 404 || code == 405) {
             break;
          }
        }
      }
    }
    throw Exception('当前系统未安装适配的打赏插件，或该接口已被隐藏。');
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
