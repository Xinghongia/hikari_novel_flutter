import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart' as ckjar;
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/foundation.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/custom_exception.dart';
import 'package:hikari_novel_flutter/models/resource.dart';

import '../common/log.dart';
import '../models/common/charsets_type.dart';
import '../service/local_storage_service.dart';
import 'api.dart';

/// 网络请求层
///
/// 负责与 wenku8 服务器的所有 HTTP 通信。
/// wenku8 不提供 JSON API，所有数据都是服务端渲染的 HTML 页面，
/// 所以这里拿到的是原始字节，需要手动 GBK/Big5 解码。
class Request {
  /// 伪装成 Chrome 浏览器的 User-Agent，避免被服务器拒绝
  static const userAgent = {
    io.HttpHeaders.userAgentHeader:
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0",
  };

  /// Cookie 存储，用于在请求中自动携带登录态
  static final _dioCookieJar = ckjar.CookieJar();

  /// Dio 实例，全局复用
  static final Dio dio =
      Dio(
          BaseOptions(
            headers: userAgent,
            // 【关键】用 bytes 模式拿原始字节，因为 wenku8 用 GBK/Big5 编码，不是 UTF-8
            // 如果用默认的 JSON/String 模式，中文会乱码
            responseType: ResponseType.bytes,
            // 【关键】禁用自动重定向，wenku8 登录后会 302 跳转，需要手动跟随以保留 Cookie
            followRedirects: false,
            // 所有 HTTP 状态码都进入拦截器处理（包括 403、302 等）
            validateStatus: (status) => status != null,
          ),
        )
        // Cloudflare 拦截器：检测 403 和人机验证
        ..interceptors.add(CloudflareInterceptor())
        // Cookie 管理器：自动在请求中携带 Cookie，自动保存服务器返回的 Cookie
        ..interceptors.add(CookieManager(_dioCookieJar));

  /// 从本地存储恢复 Cookie 到 Dio 的 CookieJar
  ///
  /// 登录成功后，Cookie 会保存到 Hive 本地存储。
  /// 应用启动时调用此方法，把 Cookie 注入到 Dio 中，
  /// 这样后续所有请求都会自动携带登录态。
  static void initCookie() {
    final localCookie = LocalStorageService.instance.getCookie();

    if (localCookie == null) return;

    // 解析 "jieqiUserInfo=xxx;jieqiVisitInfo=yyy" 格式的 Cookie 字符串
    final cookies = localCookie.split(';').map((e) => e.trim()).where((e) => e.contains('=')).map((e) {
      final kv = e.split('=');
      return ckjar.Cookie(kv[0], kv.sublist(1).join('='));
    }).toList();

    // 同时写入两个域名（wenku8 有两个镜像站）
    _dioCookieJar.saveFromResponse(Uri.parse(Wenku8Node.wwwWenku8Cc.node), cookies);
    _dioCookieJar.saveFromResponse(Uri.parse(Wenku8Node.wwwWenku8Net.node), cookies);
  }

  /// 清除所有 Cookie（退出登录时调用）
  static void deleteCookie() => _dioCookieJar.deleteAll();

  /// 获取通用数据（如 GitHub API），不用 wenku8 的 Cookie
  static Future<Resource> getCommonData(String url) async {
    try {
      final dio = Dio(BaseOptions(headers: userAgent));
      final response = await dio.get(url);
      return Success(response.data);
    } catch (e) {
      return Error(e.toString());
    }
  }

  /// 【核心方法】获取 wenku8 的 HTML 页面
  ///
  /// 完整流程：
  /// ① URL 追加 charset 参数（告诉服务器用什么编码返回）
  /// ② Dio 发起 GET 请求，拿到 Uint8List 原始字节
  /// ③ 检查 302 重定向，手动跟随（保留 Cookie）
  /// ④ GBK/Big5 解码，把字节流转成 Dart String
  /// ⑤ 包装成 Success(html) 返回
  static Future<Resource> get(String url, {required CharsetsType charsetsType}) async {
    try {
      // ① 追加 charset 参数
      if (!url.contains("?")) url += "?";
      switch (charsetsType) {
        case CharsetsType.gbk:
          url += "&charset=gbk";
        case CharsetsType.big5Hkscs:
          url += "&charset=big5";
      }

      Log.d("$url ${charsetsType.name}");

      // ② 发起 GET 请求（response.data 是 Uint8List，因为上面配置了 ResponseType.bytes）
      final response = await dio.get(url);

      // ③ 检查 302 重定向（wenku8 登录后会跳转，需要手动跟随）
      final result = await _checkRedirects(response);

      // ④ 把字节流解码成字符串
      final raw = result as Uint8List;
      late String decodedHtml;
      switch (charsetsType) {
        case CharsetsType.gbk:
          // GBK 解码：简体中文页面
          decodedHtml = GbkDecoder().convert(raw);
        case CharsetsType.big5Hkscs:
          // Big5 解码：繁体中文页面
          decodedHtml = Big5Decoder().convert(raw);
      }

      // ⑤ 返回解码后的 HTML 字符串
      return Success(decodedHtml);
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }

  /// 检查 302 重定向并手动跟随
  ///
  /// 为什么要手动处理？因为 Dio 默认的重定向不保留 Cookie，
  /// 而 wenku8 的登录态依赖 Cookie，必须带着 Cookie 跟随重定向。
  static Future<dynamic> _checkRedirects(Response response) async {
    if (response.statusCode != null && response.statusCode! >= 300 && response.statusCode! < 400) {
      final location = response.headers.value('location');
      if (location != null) {
        // 手动发起重定向请求（Dio 实例自带 Cookie，会自动携带）
        final redirectedResponse = await dio.get("${Api.wenku8Node.node}/$location");
        return redirectedResponse.data;
      }
    }
    // 不是 302，直接返回原始数据
    return response.data;
  }

  /// 以 POST 方法发送表单数据
  ///
  /// 用于发表评论、回复、批量操作书架等写入操作。
  /// Content-Type: application/x-www-form-urlencoded
  ///
  /// 注意：当 body 含有 URL 编码的中文时，data 必须用 String 类型，
  /// 不能用 Map，否则 Dio 会二次编码导致乱码。
  static Future<Resource> postForm(String url, {required Object? data, required CharsetsType charsetsType}) async {
    try {
      final response = await dio.post(
        url,
        data: data,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      // 同样需要手动 GBK/Big5 解码
      String decodedHtml;
      switch (charsetsType) {
        case CharsetsType.gbk:
          {
            decodedHtml = GbkCodec().decode(response.data as Uint8List);
          }
        case CharsetsType.big5Hkscs:
          {
            decodedHtml = Big5Codec().decode(response.data as Uint8List);
          }
      }
      return Success(decodedHtml);
    } catch (e) {
      Log.e(e.toString());
      return Error(e.toString());
    }
  }
}

class CloudflareInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final statusCode = response.statusCode;
    if (statusCode == 403) {
      handler.reject(Cloudflare403Exception(requestOptions: response.requestOptions));
      return;
    }

    final cfMitigated = response.headers['cf-mitigated'];
    if (cfMitigated == null || !cfMitigated.contains('challenge')) {
      handler.next(response);
      return;
    }
    handler.reject(CloudflareChallengeException(requestOptions: response.requestOptions));
  }
}