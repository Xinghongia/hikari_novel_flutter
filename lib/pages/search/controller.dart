import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/network/parser.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';

import '../../common/database/database.dart';
import '../../network/api.dart';
import '../../service/db_service.dart';
import '../../widgets/state_page.dart';

class SearchController extends GetxController {
  SearchController({required this.author});

  final String? author;

  final keywordController = TextEditingController();

  RxInt searchMode = 0.obs;
  RxList<String> searchHistory = RxList();

  Rx<PageState> pageState = Rx(PageState.pleaseSelect);

  String errorMsg = "";

  int _maxNum = 1;
  int _index = 0;
  final RxList<NovelCover> data = RxList();

  @override
  void onReady() {
    super.onReady();

    DBService.instance.getAllSearchHistory().listen((sh) => searchHistory.assignAll(sh.reversed.map((e) => e.keyword)));

    checkIsAuthorSearch(author);
  }

  void checkIsAuthorSearch(String? author) {
    if (author != null) {
      keywordController.text = author;
      searchMode.value = 1;
      getPage(false);
    }
  }

  void searchFromHistory(String keyword) {
    keywordController.text = keyword;
    keywordController.selection = TextSelection.fromPosition(TextPosition(offset: keywordController.text.length));
    getPage(false);
    Get.focusScope?.unfocus();
  }

  void goLogin() {
    Get.toNamed(RoutePath.login);
  }

  Future<IndicatorResult> getPage(bool loadMore) async {
    if (!loadMore) pageState.value = PageState.loading;

    if (!loadMore) {
      DBService.instance.upsertSearchHistory(SearchHistoryEntityData(keyword: keywordController.text));

      data.clear();
      _index = 0;
    }
    if (_index >= _maxNum) {
      return IndicatorResult.noMore;
    }
    _index += 1;

    Resource result;
    if (searchMode.value == 0) {
      result = await Api.searchNovelByTitle(title: keywordController.text, index: _index);
    } else {
      result = await Api.searchNovelByAuthor(author: keywordController.text, index: _index);
    }

    switch (result) {
      case Success():
        {
          final html = result.data;

          // 检查是否是错误页面（需要登录）
          if (Parser.isError(html)) {
            if (!loadMore) {
              errorMsg = "need_login_to_browse".tr;
              pageState.value = PageState.needLogin;
            } else {
              Get.dialog(
                AlertDialog(
                  title: Text("warning".tr),
                  content: Text("need_login_to_browse".tr),
                  actions: [TextButton(onPressed: Get.back, child: Text("confirm".tr))],
                ),
              );
            }

            return IndicatorResult.fail;
          }

          final onlyOne = Parser.isSearchResultOnlyOne(html);

          if (!loadMore) {
            _maxNum = (onlyOne != null) ? 1 : Parser.getMaxNum(html);
          }

          final parsedHtml = (onlyOne != null) ? <NovelCover>[onlyOne] : Parser.parseToList(html);

          if (parsedHtml.isEmpty) {
            pageState.value = PageState.empty;
            return IndicatorResult.noMore;
          }

          data.addAll(parsedHtml);
          if (!loadMore) pageState.value = PageState.success;
          return (onlyOne != null) ? IndicatorResult.noMore : IndicatorResult.success;
        }
      case Error():
        {
          if (!loadMore) {
            errorMsg = result.error;
            pageState.value = PageState.error;
          } else {
            showErrorDialog(result.error.toString(), [TextButton(onPressed: Get.back, child: Text("confirm".tr))]);
          }
          if (_index > 0) {
            _index -= 1;
          }
          return IndicatorResult.fail;
        }
    }
  }
}
