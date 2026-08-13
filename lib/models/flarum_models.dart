// 文件位置: lib/models/flarum_models.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
  final String badgesCount; 
  final List<FlarumGroup> groups;

  FlarumUser({
    required this.id, 
    required this.username, 
    required this.displayName, 
    this.avatarUrl,
    this.money = '0',
    this.likesReceived = '0',
    this.badgesCount = '0',
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
  final String? template; // [核心修复：新增模板字段支撑发帖模板功能]

  FlarumTag({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.color,
    this.isPrimary = false,
    this.position,
    this.canStartDiscussion = true,
    this.template,
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

  final allGroups = _extractGroups(included);
  List<FlarumGroup> userGroups = [];
  
  final groupsRel = rels['groups'] as Map<String, dynamic>?;
  final groupData = groupsRel?['data'] as List<dynamic>? ?? [];
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
    likesReceived: attrs['likesReceived']?.toString() ?? 
                   attrs['likes_received']?.toString() ??
                   attrs['votes']?.toString() ?? 
                   attrs['points']?.toString() ?? 
                   attrs['likesCount']?.toString() ?? 
                   attrs['likes']?.toString() ?? 
                   attrs['reputation']?.toString() ?? 
                   '0',
    badgesCount: attrs['badgesCount']?.toString() ??
                 attrs['level']?.toString() ??
                 (rels['userBadges']?['data'] as List?)?.length.toString() ??
                 (rels['badges']?['data'] as List?)?.length.toString() ??
                 '0',
    groups: userGroups, 
  );
}

List<FlarumTag> parseTags(Map<String, dynamic> json) {
  final data = json['data'] as List<dynamic>? ?? [];
  return data.map((item) {
    final attrs = item['attributes'] ?? {};
    
    final pos = attrs['position'];
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
      // [核心修复：深度嗅探解析插件携带的模板字段]
      template: attrs['discussionTemplate']?.toString() ?? attrs['template']?.toString(),
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
      final groupsRel = rels['groups'] as Map<String, dynamic>?;
      final groupData = groupsRel?['data'] as List<dynamic>? ?? [];
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
        likesReceived: attrs['likesReceived']?.toString() ?? 
                       attrs['likes_received']?.toString() ??
                       attrs['votes']?.toString() ?? 
                       attrs['points']?.toString() ?? 
                       attrs['likesCount']?.toString() ?? 
                       '0',
        badgesCount: attrs['badgesCount']?.toString() ??
                     attrs['level']?.toString() ??
                     (rels['userBadges']?['data'] as List?)?.length.toString() ??
                     (rels['badges']?['data'] as List?)?.length.toString() ??
                     '0',
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

dynamic getFontAwesomeIcon(String? iconClass) {
  if (iconClass == null || iconClass.isEmpty) return FontAwesomeIcons.certificate;
  final lower = iconClass.toLowerCase();
  if (lower.contains('crown')) return FontAwesomeIcons.crown; 
  if (lower.contains('wrench')) return FontAwesomeIcons.wrench; 
  if (lower.contains('shield')) return FontAwesomeIcons.shieldHalved;
  if (lower.contains('star')) return FontAwesomeIcons.solidStar;
  if (lower.contains('bolt')) return FontAwesomeIcons.bolt;
  if (lower.contains('medal')) return FontAwesomeIcons.medal; 
  if (lower.contains('award')) return FontAwesomeIcons.award;
  if (lower.contains('thumbs-up') || lower.contains('thumbsup')) return FontAwesomeIcons.solidThumbsUp;
  if (lower.contains('gem')) return FontAwesomeIcons.gem;
  if (lower.contains('user')) return FontAwesomeIcons.solidUser;
  return FontAwesomeIcons.certificate;
}

Widget buildUserBadges(List<FlarumGroup> groups) {
  if (groups.isEmpty) return const SizedBox.shrink();
  
  return Wrap(
    spacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: groups.map((g) {
      Color bgColor = Colors.grey;
      if (g.color != null && g.color!.isNotEmpty) {
        String hex = g.color!.replaceFirst('#', '');
        if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
        if (hex.length == 6) hex = 'FF$hex';
        bgColor = Color(int.tryParse(hex, radix: 16) ?? 0xFF9E9E9E);
      }

      final hasIcon = g.icon != null && g.icon!.trim().isNotEmpty;

      if (hasIcon) {
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Center(
            child: FaIcon(getFontAwesomeIcon(g.icon), size: 10, color: Colors.white),
          ),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
          child: Text(
            g.nameSingular.isNotEmpty ? g.nameSingular : '标签', 
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, height: 1.1)
          ),
        );
      }
    }).toList(),
  );
}
