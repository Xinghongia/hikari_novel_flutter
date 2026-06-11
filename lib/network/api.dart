import 'dart:ui';

import 'package:enough_convert/enough_convert.dart';
import 'package:get/get.dart' hide Response;
import 'package:hikari_novel_flutter/common/extension.dart';
import 'package:hikari_novel_flutter/models/common/charsets_type.dart';
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/network/request.dart';

import '../service/local_storage_service.dart';

/// 接口层
///
/// 职责：拼 URL + 调用 Request 发请求。
/// 所有方法都是 static，直接通过 Api.xxx() 调用。
///
/// wenku8 的 URL 规律：
/// - 读取操作：GET 请求，参数拼在 URL 上
/// - 写入操作（评论、书架操作）：POST 请求，参数放在 body 里
///
/// 编码处理：
/// - 中文参数（分类名、搜索词）需要先编码成 GBK/Big5 字节，再做 URL 编码
/// - 因为 wenku8 服务器期望的是 GBK/Big5 编码的 URL，不是 UTF-8
class Api {
  /// 当前用户的语言设置
  static Language get _language => LocalStorageService.instance.getLanguage();

  /// 根据语言设置决定编码类型
  /// 简体中文 → GBK，繁体中文 → Big5
  static CharsetsType get charsetsType {
    if (_language == Language.followSystem) {
      if (Get.deviceLocale == Locale("zh", "CN")) {
        return CharsetsType.gbk;
      } else if (Get.deviceLocale == Locale("zh", "TW")) {
        return CharsetsType.big5Hkscs;
      } else {
        return CharsetsType.gbk;
      }
    }
    return switch (_language) {
      Language.simplifiedChinese => CharsetsType.gbk,
      Language.traditionalChinese => CharsetsType.big5Hkscs,
      _ => CharsetsType.gbk,
    };
  }

  /// 当前选择的 wenku8 节点（有两个镜像站可选）
  static Wenku8Node get wenku8Node => LocalStorageService.instance.getWenku8Node();

  /// GitHub API 地址，用于检查应用更新
  static String latestUrl = "https://api.github.com/repos/15dd/hikari_novel_flutter/releases/latest";

  /// 获取推荐页数据
  /// wenku8 首页 index.php 就是推荐页，返回 HTML
  static Future<Resource> getRecommend() {
    final String url = "${wenku8Node.node}/index.php";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 根据排名获取小说列表
  /// [ranking] 排行榜种类，如 "all_visit"（总点击）、"day_vote"（日推荐）等
  /// [index] 第几页
  static Future<Resource> getNovelByRanking({required String ranking, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/toplist.php?sort=$ranking&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 根据分类获取小说列表
  /// [category] 分类名，如 "校园"、"恋爱"（需要 GBK URL 编码）
  /// [sort] 排序方式："0"按更新、"1"按热度、"2"按完结、"3"按动画化
  /// [index] 第几页
  static Future<Resource> getNovelByCategory({required String category, required String sort, required int index}) {
    // 【关键】中文分类名需要先编码成 GBK/Big5 字节，再转 %XX 格式
    // 比如 "校园" 的 GBK 字节是 [0xD0, 0xA3, 0xD4, 0xB0]，编码后变成 "%D0%A3%D4%B0"
    switch (charsetsType) {
      case CharsetsType.gbk:
        {
          category = GbkCodec().encode(category).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join().trim();
        }
      case CharsetsType.big5Hkscs:
        {
          category = Big5Codec().encode(category).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join().trim();
        }
    }
    String url = "${wenku8Node.node}/modules/article/tags.php?t=$category&v=$sort&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取小说详情页
  /// [aid] 小说 ID，如 "12345"
  static Future<Resource> getNovelDetail({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/articleinfo.php?id=$aid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取小说的章节目录
  /// 只传 aid 时返回的是目录页，传 cid 时返回的是章节内容
  static Future<Resource> getCatalogue({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/reader.php?aid=$aid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 加入书架
  static Future<Resource> addNovel({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/addbookcase.php?bid=$aid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 从书架移除单本
  /// [delid] 书架条目的 bid（不是小说的 aid）
  static Future<Resource> removeNovel({required String delid}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php?delid=$delid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 批量从书架移除
  /// [list] 要删除的 bid 列表
  /// [classId] 从哪个书架分类中删除
  static Future<Resource> removeNovelFromList({required List<String> list, required int classId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php";
    final Map<String, dynamic> params = {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": -1, "classid": classId};
    return Request.postForm(url, data: params, charsetsType: charsetsType);
  }

  /// 批量移动到其他书架
  static Future<Resource> moveNovelToOther({required List<String> list, required int classId, required int newClassId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php";
    final Map<String, dynamic> params = {"checkid[]": list, "classlist": classId, "checkall": "checkall", "newclassid": newClassId, "classid": classId};
    return Request.postForm(url, data: params, charsetsType: charsetsType);
  }

  /// 获取书架列表
  /// [classId] 书架编号 0-5
  static Future<Resource> getBookshelf({required int classId}) {
    final String url = "${wenku8Node.node}/modules/article/bookcase.php?classid=$classId";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取其他用户的书架
  static Future<Resource> getBookshelfFromUser({required String uid}) {
    final String url = "${wenku8Node.node}/userpage.php?uid=$uid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取评论列表
  static Future<Resource> getComment({required String aid, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/reviews.php?aid=$aid&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取回复列表
  static Future<Resource> getReply({required String rid, required int index}) {
    final String url = "${wenku8Node.node}/modules/article/reviewshow.php?rid=$rid&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 为小说投票（推荐）
  static Future<Resource> novelVote({required String aid}) {
    final String url = "${wenku8Node.node}/modules/article/uservote.php?id=$aid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 按标题搜索小说
  /// [title] 搜索关键词（需要 GBK URL 编码）
  static Future<Resource> searchNovelByTitle({required String title, required int index}) {
    // 同分类一样，搜索词也需要 GBK/Big5 编码后 URL 编码
    switch (charsetsType) {
      case CharsetsType.gbk:
        title = GbkEncoder().convert(title).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
      case CharsetsType.big5Hkscs:
        title = Big5Encoder().convert(title).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
    }
    final String url = "${wenku8Node.node}/modules/article/search.php?searchtype=articlename&searchkey=$title&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 按作者搜索小说
  static Future<Resource> searchNovelByAuthor({required String author, required int index}) {
    switch (charsetsType) {
      case CharsetsType.gbk:
        author = GbkEncoder().convert(author).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
      case CharsetsType.big5Hkscs:
        author = Big5Encoder().convert(author).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
    }
    final String url = "${wenku8Node.node}/modules/article/search.php?searchtype=author&searchkey=$author&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取当前登录用户的信息
  static Future<Resource> getUserInfo() {
    final String url = "${wenku8Node.node}/userdetail.php";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取已完结小说列表
  static Future<Resource> getCompletionNovel({required int index}) {
    final String url = "${wenku8Node.node}/modules/article/articlelist.php?fullflag=1&page=$index";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 发表书评（POST 请求）
  /// [aid] 书号
  /// [title] 书评标题
  /// [content] 书评内容
  ///
  /// 注意：body 中的中文需要 URL 编码，submit 按钮的值也需要编码
  static Future<Resource> sendComment({required String aid, required String title, required String content}) {
    final String url = "${wenku8Node.node}/modules/article/reviews.php?aid=$aid";

    String submit;
    switch (charsetsType) {
      case CharsetsType.gbk:
        // "发表书评" 按钮的值也需要 GBK 编码
        submit = GbkEncoder().convert("发表书评").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        title = title.gbkUrlEncodingIfNotAscii();
        content = content.gbkUrlEncodingIfNotAscii();
      case CharsetsType.big5Hkscs:
        submit = Big5Encoder().convert("發表書評").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        title = title.big5UrlEncodingIfNotAscii();
        content = content.big5UrlEncodingIfNotAscii();
    }
    // URL 编码的空格是 "+"
    submit = "+$submit+";

    final String params = "ptitle=$title&pcontent=$content&Submit=$submit";
    return Request.postForm(url, data: params, charsetsType: charsetsType);
  }

  /// 发表回复（POST 请求）
  static Future<Resource> sendReply({required String aid, required String rid, required String content}) {
    final String url = "${wenku8Node.node}/modules/article/reviewshow.php?rid=$rid&aid=$aid";

    String submit;
    switch (charsetsType) {
      case CharsetsType.gbk:
        submit = GbkEncoder().convert("发表书评").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        content = content.gbkUrlEncodingIfNotAscii();
      case CharsetsType.big5Hkscs:
        submit = Big5Encoder().convert("發表書評").map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join();
        content = content.big5UrlEncodingIfNotAscii();
    }
    submit = "+$submit+";

    final String params = "pcontent=$content&Submit=$submit";

    return Request.postForm(url, data: params, charsetsType: charsetsType);
  }

  /// 获取章节内容
  /// [aid] 小说 ID
  /// [cid] 章节 ID
  static Future<Resource> getNovelContent({required String aid, required String cid}) {
    final String url = "${Api.wenku8Node.node}/modules/article/reader.php?aid=$aid&cid=$cid";
    return Request.get(url, charsetsType: charsetsType);
  }

  /// 获取 GitHub 上的最新版本（用通用请求，不带 wenku8 Cookie）
  static Future<Resource> fetchLatestRelease() {
    return Request.getCommonData(latestUrl);
  }
}