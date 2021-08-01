import 'package:flutter/material.dart';

abstract class DynamicSize {
  Size getSize(GlobalKey pagekey);
}

class DynamicSizeImpl extends DynamicSize {
  @override
  Size getSize(GlobalKey<State<StatefulWidget>> pageKey) {
    final RenderBox _pageBox =
        pageKey.currentContext!.findRenderObject() as RenderBox;
    return _pageBox.size;
  }
}
