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
    final response = await _dio.get('/api/discussions/$id', queryParameters: {
      'page[number]': page, 
      'page[size]': pageSize, 
      'include': 'user,posts,posts.user'
    });
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

  // [终极矩阵探针：完全无视 404 返回码的具体内容，只认非 404 成功门槛]
  Future<void> buyPost(List<String> possibleIds, int discussionId, int postId) async {
    DioException? bestRouteErr;
    
    // 全覆盖所有衍生路由
    final routeTemplates = [
      '/api/pay-to-read/{id}',
      '/api/paytoread/{id}',
      '/api/pay-to-read/{id}/purchase',
      '/api/pay-to-read/{id}/buy',
      '/api/pay-to-see/{id}',
      '/api/paytosee/{id}',
      '/api/posts/{id}/pay-to-read',
      '/api/discussions/{id}/pay-to-read',
      '/api/posts/{id}/pay',
      '/api/discussions/{id}/pay',
      '/api/posts/{id}/purchase',
      '/api/discussions/{id}/purchase',
      '/api/posts/{id}/buy',
      '/api/ziiven/paytoread/{id}',
      '/api/ziiven/pay/{id}',
      '/api/pay/{id}',
    ];

    final noIdRoutes = [
      '/api/pay-to-read',
      '/api/paytoread',
      '/api/pay-to-see',
      '/api/purchases',
      '/api/orders',
    ];

    // 标准 Flarum JSON API 全套开门钥匙
    final payloads = [
      {"data": {}},
      {"data": {"type": "paytoread", "attributes": {}}},
      {"data": {"type": "pay-to-read", "attributes": {}}},
      {"data": {"attributes": {"pay": true}}},
      {"pay": true},
      {"data": {"attributes": {"post_id": postId}}},
      {"data": {"relationships": {"post": {"data": {"type": "posts", "id": postId.toString()}}}}},
      {"data": {"relationships": {"discussion": {"data": {"type": "discussions", "id": discussionId.toString()}}}}},
    ];

    final allUrls = <String>[];
    for (var tmpl in routeTemplates) {
      for (var id in possibleIds) {
        allUrls.add(tmpl.replaceAll('{id}', id));
      }
    }
    allUrls.addAll(noIdRoutes);

    // 跨越 POST 与 PUT 进行暴力破拆
    for (final method in ['POST', 'PUT']) {
      for (final ep in allUrls) {
        bool isRoute404 = false;

        for (final p in payloads) {
          try {
            if (method == 'POST') {
              await _dio.post(ep, data: p);
            } else {
              await _dio.put(ep, data: p);
            }
            return; // HTTP 200/201: 交易直接成功！
          } on DioException catch (e) {
            final code = e.response?.statusCode;
            
            // 核心剪枝：遇到任何形式的 404 或 405，立马停止当前 URL 的挣扎，直接短路测下一个！毫秒级响应！
            if (code == 404 || code == 405) {
               isRoute404 = true;
               break; 
            }
            
            // 如果跑到这，说明遇到了 422、400、403，意味着我们找对了门！
            bestRouteErr = e;
            
            final resStr = e.response?.data?.toString() ?? '';
            // 如果报错里出现资金相关的业务拦截，直接将这个最正确的阻碍抛出！
            if (RegExp(r'不足|enough|余额|fund|权限|不能|支付|buy|XSD|积分|金币|购买', caseSensitive: false).hasMatch(resStr) || code == 403) {
              throw e; 
            }
          }
        }
        
        // 如果上面被 404 短路了，赶紧测下一个 URL
        if (isRoute404) continue;

        // 如果这个路由是真实存在的（触发了 422 等），但所有合法载荷都进不去，就将这个路由的真实反馈抛出保底
        if (bestRouteErr != null) {
          throw bestRouteErr;
        }
      }
    }

    throw Exception('API_ROUTE_UNMATCHED');
  }

  // 同步修复打赏接口
  Future<void> tipPost(int postId, int amount) async {
    DioException? bestErr;
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
      bool isRoute404 = false;
      for (final p in payloads) {
        try {
          await _dio.post(ep, data: p);
          return;
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 404 || code == 405) {
             isRoute404 = true;
             break; 
          }
          bestErr = e;
          if (code == 422) continue;
          throw e; // 直接抛出实际业务报错
        }
      }
      if (isRoute404) continue;
      if (bestErr != null) throw bestErr;
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

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
  
  Future<void> _saveAuth(String token, int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (userId != null) await prefs.setInt(_userIdKey, userId);
  }
}
