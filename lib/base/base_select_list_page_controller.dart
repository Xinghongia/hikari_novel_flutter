import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';
import 'package:hikari_novel_flutter/widgets/state_page.dart';

import '../models/page_state.dart';
import '../models/resource.dart';
import '../network/parser.dart';

abstract class BaseSelectListPageController<T> extends GetxController {
  final EasyRefreshController easyRefreshController = EasyRefreshController();

  /// ###### 页面初始状态
  Rx<PageState> pageState = Rx(PageState.pleaseSelect);
  String errorMsg = "";

  int _maxNum = 1;
  int _index = 0;
  final RxList<T> data = RxList();

  Future<Resource> getData(int index);

  List<T> getParser(String html);

  void goLogin() {
    Get.toNamed(RoutePath.login);
  }

  Future<IndicatorResult> getPage(bool loadMore) async {
    if (!loadMore) {
      pageState.value = PageState.loading;
      data.clear();
      _index = 0;
    }
    if (_index >= _maxNum) {
      return IndicatorResult.noMore;
    }
    _index += 1;
    final result = await getData(_index);

    switch (result) {
      case Success(): {
        // 检查是否是错误页面（需要登录）
        if (Parser.isError(result.data)) {
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
          if (_index > 0) {
            _index -= 1;
          }
          return IndicatorResult.fail;
        }

        if (!loadMore) {
          _maxNum = Parser.getMaxNum(result.data);
        }
        data.addAll(getParser(result.data));

        pageState.value = PageState.success;
        return IndicatorResult.success;
      }
      case Error(): {
        if (!loadMore) {
          pageState.value = PageState.error;
          errorMsg = result.error;
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