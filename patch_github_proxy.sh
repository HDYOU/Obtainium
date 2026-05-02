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
# 1. 添加双代理配置项
# ==========================
echo "⇒ 添加双代理配置项"
sed -i '/sourceConfigSettingFormItems = \[/a\
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
sed -i '/possibleBuildGradleLocations = \[/a\
      "/app/build.gradle.kts",\
      "android/app/build.gradle.kts",\
      "src/app/build.gradle.kts",\
   ' "$FILE"
echo "fix applicationId"
sed -i "/l.startsWith('applicationId \"') ||/a\\
      l.startsWith('applicationId =') ||
   " "$FILE"
echo "fix appid"
sed -i '/appId.split\(/,/^            \);$/c\
      RegExp(r"""(applicationId|namespace)\s*[=]?\s*["\']([^"\'\s]+)["\']""").firstMatch(appId)?.group(2) ??"", );\
    ' "$FILE"
# ==========================
# 2. 注释 APK 请求头
# ==========================
echo "⇒ 注释 application/octet-stream"
sed -i '/application\/octet-stream/s/^/\/\//' "$FILE"

# ==========================
# 3. 修复 URL 顺序
# ==========================
echo "⇒ 修复 URL 获取顺序"
sed -i 's/(e\['\''url'\''] ?? e\['\''browser_download_url'\''])/(e['\''browser_download_url'\''] ?? e['\''url'\''])/g' "$FILE"

# ==========================
# 4. 增强 undoGHProxyMod
# ==========================
echo "⇒ 升级代理还原方法"
sed -i '/reqUrl.replaceFirst/a\
    "https://${sourceConfigSettingValues[\"GHProxyPrefix\"]}/",\
    ""\
  ).replaceFirst(\
    "https://${sourceConfigSettingValues[\"GHProxyDownloadPrefix\"]}/",\
    ""\
  ).replaceFirst(\
    ' "$FILE"

# ==========================
# 5.0 设置 sourceConfigSettingValues
# ==========================
echo "⇒ 设置sourceConfigSettingValues"
if ! grep -q "rateLimitErrorCheck" "$FILE"; then
sed -i '/rateLimitErrorCheck.*{/i\
  Future<Map> getSourceConfigSettingValues() {\
    var sp = SettingsProvider();\
    await sp.initializeSettings();\
    var sourceConfigSettingValues = await getSourceConfigValues({}, sp);\
    return sourceConfigSettingValues;\
  }' "$FILE"
fi

# ==========================
# 5. API 请求加代理
# ==========================
echo "⇒ API 请求自动加代理"
#sed -i 's/apiUrl/&.notFoundAndAppendHost((await getSourceConfigSettingValues())\[\"GHProxyPrefix\"\])/g' "$FILE"
sed -i 's/sourceRequest([^,]+/&.notFoundAndAppendHost((await getSourceConfigSettingValues())\[\"GHProxyPrefix\"\])/g' "$FILE"
sed -i 's/Component(query)}\&per_page=100[^,]+/&.notFoundAndAppendHost((await getSourceConfigSettingValues())\[\"GHProxyPrefix\"\])/g' "$FILE"

# ==========================
# 6. 下载代理方法
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
    return assetUrl.notFoundAndAppendHost(sourceConfigSettingValues\[\"GHProxyDownloadPrefix\"\]);\
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

cat "$FILE"