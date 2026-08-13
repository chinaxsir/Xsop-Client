// 文件位置: lib/models/flarum_models.dart

import 'package:flutter/material.dart';

// [修改备注：新增 Flarum 用户组（徽章）实体模型]
class FlarumGroup {
  final String id;
  final String nameSingular;
  final String namePlural;
  final String? color;
  final String? icon;

  FlarumGroup({required this.id, required this.nameSingular, required this.namePlural, this.color, this.icon});
}

class FlarumUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String money; 
  final String likesReceived;
  // [修改备注：用户关联的所有徽章/用户组]
  final List<FlarumGroup> groups;

  FlarumUser({
    required this.id, 
    required this.username, 
    required this.displayName, 
    this.avatarUrl,
    this.money = '0',
    this.likesReceived = '0',
    this.groups = const [],
  });
}

class FlarumTag {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? color;
  final bool isPrimary; 
  final int? position; 
  final bool canStartDiscussion;

  FlarumTag({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.color,
    this.isPrimary = false,
    this.position,
    this.canStartDiscussion = true,
  });
}

class Discussion {
  final String id;
  final String title;
  final int commentCount;
  final DateTime createdAt;
  final FlarumUser? user;
  final FlarumUser? lastPostedUser;
  final DateTime? lastPostedAt;
  final List<FlarumTag> tags;

  Discussion({
    required this.id,
    required this.title,
    required this.commentCount,
    required this.createdAt,
    this.user,
    this.lastPostedUser,
    this.lastPostedAt,
    required this.tags,
  });
}

class DiscussionList {
  final List<Discussion> items;
  final bool hasMore;
  DiscussionList(this.items, this.hasMore);
}

// 提取全局 groups 的辅助方法
Map<String, FlarumGroup> _extractGroups(List<dynamic> included) {
  final Map<String, FlarumGroup> allGroups = {};
  for (var item in included) {
    if (item['type'] == 'groups') {
      final gAttrs = item['attributes'] ?? {};
      allGroups[item['id'].toString()] = FlarumGroup(
        id: item['id'].toString(),
        nameSingular: gAttrs['nameSingular'] ?? '',
        namePlural: gAttrs['namePlural'] ?? '',
        color: gAttrs['color'],
        icon: gAttrs['icon'],
      );
    }
  }
  return allGroups;
}

FlarumUser parseUser(Map<String, dynamic> json, String baseUrl) {
  final data = json['data'] ?? {};
  final attrs = data['attributes'] ?? {};
  final rels = data['relationships'] ?? {};
  final included = json['included'] as List<dynamic>? ?? [];

  // 解析并映射徽章关系
  final allGroups = _extractGroups(included);
  List<FlarumGroup> userGroups = [];
  final groupData = rels['groups']?['data'] as List<dynamic>? ?? [];
  for (var g in groupData) {
    final gId = g['id'].toString();
    if (allGroups.containsKey(gId)) {
      userGroups.add(allGroups[gId]!);
    }
  }

  String? avatar = attrs['avatarUrl'];
  if (avatar != null && avatar.startsWith('/')) {
    avatar = '$baseUrl$avatar';
  }
  return FlarumUser(
    id: data['id'].toString(),
    username: attrs['username'] ?? 'Unknown',
    displayName: attrs['displayName'] ?? attrs['username'] ?? 'Unknown',
    avatarUrl: avatar,
    money: attrs['money']?.toString() ?? '0',
    likesReceived: attrs['likesReceived']?.toString() ?? '0',
    groups: userGroups, // 挂载徽章
  );
}

List<FlarumTag> parseTags(Map<String, dynamic> json) {
  final data = json['data'] as List<dynamic>? ?? [];
  return data.map((item) {
    final attrs = item['attributes'] ?? {};
    
    final pos = attrs['position'];
    // [核心修复1：Flarum 官方极致鉴定法！只有 position 为纯数字的才是主标签，彻底杜绝所有空字符串和 null 的干扰]
    bool isPrimary = false;
    if (pos is int) {
      isPrimary = true;
    } else if (pos is String && int.tryParse(pos) != null) {
      isPrimary = true;
    }

    return FlarumTag(
      id: item['id'].toString(),
      name: attrs['name'] ?? '',
      slug: attrs['slug'] ?? '',
      description: attrs['description'],
      color: attrs['color'],
      isPrimary: isPrimary,
      position: pos is int ? pos : int.tryParse(pos?.toString() ?? ''),
      canStartDiscussion: attrs['canStartDiscussion'] ?? true,
    );
  }).toList();
}

DiscussionList parseDiscussionList(Map<String, dynamic> json, String baseUrl) {
  final data = json['data'] as List<dynamic>? ?? [];
  final included = json['included'] as List<dynamic>? ?? [];
  
  final Map<String, FlarumUser> users = {};
  final Map<String, FlarumTag> tags = {};
  final allGroups = _extractGroups(included);

  for (var item in included) {
    if (item['type'] == 'users') {
      final attrs = item['attributes'] ?? {};
      final rels = item['relationships'] ?? {};
      
      List<FlarumGroup> userGroups = [];
      final groupData = rels['groups']?['data'] as List<dynamic>? ?? [];
      for (var g in groupData) {
        if (allGroups.containsKey(g['id'].toString())) {
          userGroups.add(allGroups[g['id'].toString()]!);
        }
      }

      String? avatar = attrs['avatarUrl'];
      if (avatar != null && avatar.startsWith('/')) avatar = '$baseUrl$avatar';
      
      users[item['id'].toString()] = FlarumUser(
        id: item['id'].toString(),
        username: attrs['username'] ?? '',
        displayName: attrs['displayName'] ?? attrs['username'] ?? '',
        avatarUrl: avatar,
        money: attrs['money']?.toString() ?? '0',
        likesReceived: attrs['likesReceived']?.toString() ?? '0',
        groups: userGroups,
      );
    } else if (item['type'] == 'tags') {
      final attrs = item['attributes'] ?? {};
      final pos = attrs['position'];
      bool isPrimary = false;
      if (pos is int) isPrimary = true;
      else if (pos is String && int.tryParse(pos) != null) isPrimary = true;

      tags[item['id'].toString()] = FlarumTag(
        id: item['id'].toString(),
        name: attrs['name'] ?? '',
        slug: attrs['slug'] ?? '',
        color: attrs['color'],
        isPrimary: isPrimary,
      );
    }
  }

  final items = data.map((item) {
    final attrs = item['attributes'] ?? {};
    final rels = item['relationships'] ?? {};
    
    final userId = rels['user']?['data']?['id']?.toString();
    final lastUserId = rels['lastPostedUser']?['data']?['id']?.toString();
    
    final tagData = rels['tags']?['data'] as List<dynamic>? ?? [];
    final discussionTags = tagData
        .map((t) => tags[t['id'].toString()])
        .whereType<FlarumTag>()
        .toList();

    return Discussion(
      id: item['id'].toString(),
      title: attrs['title'] ?? '',
      commentCount: attrs['commentCount'] ?? 0,
      createdAt: DateTime.tryParse(attrs['createdAt'] ?? '') ?? DateTime.now(),
      user: userId != null ? users[userId] : null,
      lastPostedUser: lastUserId != null ? users[lastUserId] : null,
      lastPostedAt: attrs['lastPostedAt'] != null ? DateTime.tryParse(attrs['lastPostedAt']) : null,
      tags: discussionTags,
    );
  }).toList();

  final links = json['links'] ?? {};
  final hasMore = links['next'] != null;

  return DiscussionList(items, hasMore);
}

// [修改备注：提供全局调用的徽章 UI 生成器]
Widget buildUserBadges(List<FlarumGroup> groups) {
  if (groups.isEmpty) return const SizedBox.shrink();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: groups.map((g) {
      Color bgColor = Colors.grey;
      if (g.color != null) {
        String hex = g.color!.replaceFirst('#', '');
        if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
        if (hex.length == 6) hex = 'FF$hex';
        bgColor = Color(int.tryParse(hex, radix: 16) ?? 0xFF9E9E9E);
      }

      IconData iconData = Icons.verified_user;
      if (g.icon != null) {
        final i = g.icon!.toLowerCase();
        if (i.contains('wrench')) iconData = Icons.build;
        else if (i.contains('crown')) iconData = Icons.workspace_premium;
        else if (i.contains('star')) iconData = Icons.star;
        else if (i.contains('shield')) iconData = Icons.security;
        else if (i.contains('bolt')) iconData = Icons.bolt;
      }

      return Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
        child: Icon(iconData, size: 12, color: Colors.white),
      );
    }).toList(),
  );
}
