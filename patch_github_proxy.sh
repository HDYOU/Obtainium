#!/bin/bash
set -e
echo "============================================="
echo "  GitHub.dart 完整增强补丁（含URL顺序修复）"
echo "============================================="

FILE="lib/app_sources/github.dart"

if [ ! -f "$FILE" ]; then
  echo "⚠️  文件不存在：$FILE"
  exit 0
fi

cp "$FILE" "$FILE.bak"
echo "✅ 已备份原文件"

# ==========================
# 1. 添加 GHProxyPrefix + GHProxyDownloadPrefix
# ==========================
echo "⇒ 添加双代理配置项"
sed -i '/sourceConfigSettingFormItems = [/a\
      GeneratedFormTextField(\
        "GHProxyPrefix",\
        label: tr("GHProxyPrefix"),\
        hint: "gh.llkk.cc",\
        required: false,\
        additionalValidators: [\
          (value) {\
            try {\
              if (value != null && Uri.parse(value).scheme.isNotEmpty) {\
                throw true;\
              }\
              if (value != null) {\
                Uri.parse("https://${value}/https://api.github.com");\
              }\
            } catch (e) {\
              return tr("invalidInput");\
            }\
            return null;\
          },\
        ],\
      ),\
      GeneratedFormTextField(\
        "GHProxyDownloadPrefix",\
        label: tr("GHProxyDownloadPrefix"),\
        hint: "ghfast.top",\
        required: false,\
        additionalValidators: [\
          (value) {\
            try {\
              if (value != null && Uri.parse(value).scheme.isNotEmpty) {\
                throw true;\
              }\
              if (value != null) {\
                Uri.parse("https://${value}/https://www.github.com");\
              }\
            } catch (e) {\
              return tr("invalidInput");\
            }\
            return null;\
          },\
        ],\
      ),\
      ' "$FILE"

# ==============================================
 # 2. 替换 tryInferringAppId 逻辑
 # ==============================================
 echo "⇒ 替换 tryInferringAppId 逻辑 "
 sed -i '/Future<String?> tryInferringAppId/,/^  }$/c\
   @override\
   Future<String?> tryInferringAppId(\
     String standardUrl, {\
     Map<String, dynamic> additionalSettings = const {},\
   }) async {\
     const possibleBuildGradleLocations = [\
       '\''/app/build.gradle'\'','\
       '\''android/app/build.gradle'\'','\
       '\''src/app/build.gradle'\'','\
       '\''/app/build.gradle.kts'\'','\
       '\''android/app/build.gradle.kts'\'','\
       '\''src/app/build.gradle.kts'\'','\
     ];\
     SettingsProvider settingsProvider = SettingsProvider();\
     await settingsProvider.initializeSettings();\
     var sourceConfigSettingValues = await getSourceConfigValues(\
       additionalSettings,\
       settingsProvider,\
     );\
     for (var path in possibleBuildGradleLocations) {\
       try {\
         var res = await sourceRequest(\
           '\''${await convertStandardUrlToAPIUrl(standardUrl, additionalSettings)}/contents/$path'\'\''.notFoundAndAppendHost(sourceConfigSettingValues['\''GHProxyPrefix'\'']),\
           additionalSettings,\
         );\
         if (res.statusCode == 200) {\
           try {\
             var body = jsonDecode(res.body);\
             var trimmedLines = utf8\
                 .decode(\
                   base64.decode(\
                     body['\''content'\''].toString().split('\''\n'\'').join('\'''\''),\
                   ),\
                 )\
                 .split('\''\n'\'')\
                 .map((e) => e.trim());\
             var appIds = trimmedLines.where(\
               (l) =>\
                   l.startsWith('\''applicationId "'\'') ||\
                   l.startsWith('\''applicationId \''\'') || l.startsWith('\''applicationId ='\'')\
               ,\
             );\
             appIds = appIds.map(\
               (appId) => RegExp(r''''''(applicationId|namespace)\\s*[=]?\\s*["'"']([^"'"'\\s]+)["'"']''''''').firstMatch(appId)?.group(2) ??'''',\
             );\
             appIds = appIds\
                 .map((appId) {\
                   if (appId.startsWith('\''${'\'') && appId.endsWith('\''}'\'') {\
                     appId = trimmedLines\
                         .where(\
                           (l) => l.startsWith(\
                             '\''def ${appId.substring(2, appId.length - 1)}'\'','\
                           ),\
                         )\
                         .first;\
                     appId = appId.split(appId.contains('\''"'\'') ? '\''"'\'': '\''\'\'')[1];\
                   }\
                   return appId;\
                 })\
                 .where((appId) => appId.isNotEmpty);\
             if (appIds.length == 1) {\
               return appIds.first;\
             }\
           } catch (err) {\
             LogsProvider().add(\
               '\''Error parsing build.gradle from ${res.request!.url.toString()}: ${err.toString()}'\'','\
             );\
           }\
         }\
       } catch (err) {\
         // Ignore - ID will be extracted from the APK\
       }\
     }\
     return null;\
   }' "$TARGET_FILE"

# ==========================
# 2. 注释 APK 请求头
# ==========================
echo "⇒ 注释 application/octet-stream"
# sed -i '/forAPKDownload/s/^/\/\//' "$FILE"
sed -i '/application\/octet-stream/s/^/\/\//' "$FILE"

# ==========================
# 3. 修复关键顺序：(e['url'] ?? e['browser_download_url']) → (e['browser_download_url'] ?? e['url'])
# ==========================
echo "⇒ 修复 URL 获取顺序（browser_download_url 优先）"
sed -i 's/(e\['\''url'\''] ?? e\['\''browser_download_url'\''])/(e['\''browser_download_url'\''] ?? e['\''url'\''])/g' "$FILE"

# ==========================
# 4. 增强 undoGHProxyMod
# ==========================
echo "⇒ 升级代理还原方法"
sed -i '/reqUrl.replaceFirst/a\
    "https://${sourceConfigSettingValues["GHProxyPrefix"]}/",\
    ""\
  ).replaceFirst(\
    "https://${sourceConfigSettingValues["GHProxyDownloadPrefix"]}/",\
    ""\
  ).replaceFirst(\
    ' "$FILE"

# ==========================
# 5. API 请求加代理
# ==========================
echo "⇒ API 请求自动加代理"
sed -i 's/apiUrl/&.notFoundAndAppendHost(sourceConfigSettingValues["GHProxyPrefix"])/g' "$FILE"
sed -i 's/requestUrl/&.notFoundAndAppendHost(sourceConfigSettingValues["GHProxyPrefix"])/g' "$FILE"

# ==========================
# 6. 下载代理 assetUrlPrefetchModifier
# ==========================
echo "⇒ 添加下载代理方法"
if ! grep -q "assetUrlPrefetchModifier" "$FILE"; then
sed -i '/rateLimitErrorCheck.*{/i\
  @override\
  Future<String> assetUrlPrefetchModifier(\
      String assetUrl,\
      String standardUrl,\
      Map<String, dynamic> additionalSettings,\
      ) async {\
    var sp = SettingsProvider();\
    await sp.initializeSettings();\
    var sourceConfigSettingValues = await getSourceConfigValues(additionalSettings, sp);\
    return assetUrl.notFoundAndAppendHost(sourceConfigSettingValues["GHProxyDownloadPrefix"]);\
  }' "$FILE"
fi

# ==========================
# 7. 字符串扩展
# ==========================
echo "⇒ 添加 StringExtension"
if ! grep -q "extension StringExtension" "$FILE"; then
cat >> "$FILE" << 'EOF'

extension StringExtension on String? {
  bool get isNull => this == null;
  bool get isNullOrEmpty => this == null || this?.trim() == "";
  bool get isNotNullOrEmpty => this != null && this?.trim() != "";

  String notFoundAndAppendHost(String? host) {
    if (isNullOrEmpty) {
      return "";
    }
    var tmp = this ?? "";
    if (host.isNullOrEmpty) {
      return tmp;
    }
    return notFoundAndReplace("https://", "https://$host/https://");
  }

  String notFoundAndReplace(String from, String to) {
    if (isNullOrEmpty) {
      return "";
    }
    var tmp = this ?? "";
    if (tmp.contains(to)) {
      return tmp;
    }
    return tmp.replaceFirst(from, to);
  }
}
EOF
fi

echo -e "\n🎉 所有补丁已完成（包含URL顺序修复）"
