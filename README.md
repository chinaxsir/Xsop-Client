# XSOP Forum — 构建指南


## 📁 项目结构

```
XSOP-Forum/
├── lib/
│   ├── api/
│   │   └── api_client.dart    # API 客户端
│   ├── models/
│   │   └── flarum_models.dart # JSON:API 数据模型
│   ├── pages/
│   │   └── home_page.dart     # 首页 UI
│   └── main.dart              # 应用入口
├── ios/
│   ├── Runner/
│   │   ├── Info.plist         # 配置（含后台模式、权限说明）
│   │   ├── Runner.entitlements # TrollStore 扩展权限
│   │   └── AppDelegate.swift  # iOS 入口
│   └── Podfile                # CocoaPods 配置（已禁签名）
|── assets
│   ├── logo.png               #桌面图标
├── pubspec.yaml
└── analysis_options.yaml
```

---

## ⚠️ 重要提示

1. **无需苹果开发者账号**：TrollStore 侧载完全绕过了苹果的签名和审核机制
2. **无需签名证书**：所有构建均使用 `CODE_SIGNING_ALLOWED=NO`，TrollStore 会在安装时自动签名
3. **系统版本限制**：TrollStore 支持 iOS 14.0 - 17.x（具体取决于设备和 TrollStore 版本）
4. **风险自负**：扩展权限可能导致 App 在系统更新后无法启动，或被系统安全机制拦截
