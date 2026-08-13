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
    });
    final data = _asMap(response.data);
    final token = data['token'] as String?;
    final userId = data['userId'] as int?;
    if (token != null && token.isNotEmpty) {
      await _saveAuth(token, userId);
    }
    return data;
  }

  Future<Map<String, dynamic>> getDiscussions({
    int page = 1,
    int pageSize = 20,
    String? tag,
    String? author, 
    String? sort,
  }) async {
    final query = <String, dynamic>{
      'page[number]': page,
      'page[size]': pageSize,
      // [核心修复：移除了引发 400 报错的 user.groups 白名单外参数，恢复官方默认]
    };
    
    List<String> searchQueries = [];
    
    if (tag != null && tag.isNotEmpty) {
      query['filter[tag]'] = tag.trim();
    }
    if (author != null && author.isNotEmpty) {
      searchQueries.add('author:${author.trim()}');
    }
    
    if (searchQueries.isNotEmpty) {
      query['filter[q]'] = searchQueries.join(' ');
    }
    
    if (sort != null) query['sort'] = sort;

    final response = await _dio.get('/api/discussions', queryParameters: query);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getDiscussion(
    int id, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/discussions/$id',
      queryParameters: {
        'page[number]': page,
        'page[size]': pageSize,
        // [核心修复：同样恢复为官方标准的 include 白名单，防止详情页报错]
        'include': 'user,posts,posts.user',
      },
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getTags() async {
    final response = await _dio.get(
      '/api/tags', 
      queryParameters: {'include': 'parent'}
    );
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getUser(int id) async {
    // 个人信息接口是允许请求 groups 字段的，这里保留以支持资产和徽章显示
    final response = await _dio.get('/api/users/$id', queryParameters: {'include': 'groups'});
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createDiscussion({
    required String title,
    required String content,
    List<String>? tagIds,
    List<String>? recipientUserIds,
  }) async {
    final Map<String, dynamic> relationships = {};

    if (tagIds != null && tagIds.isNotEmpty) {
      relationships["tags"] = {
        "data": tagIds.map((id) => {"type": "tags", "id": id}).toList()
      };
    }

    if (recipientUserIds != null && recipientUserIds.isNotEmpty) {
      relationships["recipientUsers"] = {
        "data": recipientUserIds.map((id) => {"type": "users", "id": id}).toList()
      };
    }

    final Map<String, dynamic> payloadData = {
      "type": "discussions",
      "attributes": {
        "title": title,
        "content": content,
      }
    };

    if (relationships.isNotEmpty) {
      payloadData["relationships"] = relationships;
    }

    final data = {"data": payloadData};

    final response = await _dio.post('/api/discussions', data: data);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createPost(int discussionId, String content) async {
    final data = {
      "data": {
        "type": "posts",
        "attributes": {"content": content},
        "relationships": {
          "discussion": {
            "data": {"type": "discussions", "id": discussionId.toString()}
          }
        }
      }
    };
    final response = await _dio.post('/api/posts', data: data);
    return _asMap(response.data);
  }

  Future<void> deletePost(int postId) async {
    await _dio.delete('/api/posts/$postId');
  }

  Future<void> likePost(int postId, bool isLiked) async {
    await _dio.patch('/api/posts/$postId', data: {
      "data": {
        "type": "posts",
        "id": postId.toString(),
        "attributes": {"isLiked": isLiked}
      }
    });
  }

  Future<void> reportPost(int postId, String reason, String? detail) async {
    await _dio.post('/api/flags', data: {
      "data": {
        "type": "flags",
        "attributes": {
          "reason": reason,
          "reasonDetail": detail ?? ""
        },
        "relationships": {
          "post": {
            "data": {"type": "posts", "id": postId.toString()}
          }
        }
      }
    });
  }

  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _dio.get('/api/notifications', queryParameters: {'include': 'fromUser,fromUser.groups'});
    return _asMap(response.data);
  }

  Future<void> suspendUser(int userId, DateTime? suspendUntil, String? reason) async {
    await _dio.patch('/api/users/$userId', data: {
      "data": {
        "type": "users",
        "id": userId.toString(),
        "attributes": {
          "suspendUntil": suspendUntil?.toIso8601String(),
          "suspendMessage": reason
        }
      }
    });
  }

  Future<String?> uploadImage(String filePath) async {
    final formData = FormData.fromMap({
      'files[]': await MultipartFile.fromFile(filePath),
    });
    
    final response = await _dio.post('/api/fof/upload', data: formData);
    final data = _asMap(response.data);
    
    final files = data['data'] as List<dynamic>?;
    if (files != null && files.isNotEmpty) {
       return files.first['attributes']?['url'] as String?;
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

  Future<void> _saveAuth(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (userId != null) {
      await prefs.setInt(_userIdKey, userId);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
