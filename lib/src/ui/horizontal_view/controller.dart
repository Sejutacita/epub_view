import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/ui/horizontal_view/dynamic_size.dart';
import 'package:epub_view/src/ui/horizontal_view/splitted_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PageControlBloc extends Cubit<int> {
  PageControlBloc() : super(0);

  DynamicSize _dynamicSize = DynamicSizeImpl();
  SplittedText _splittedText = SplittedTextImpl();
  Size? _size;
  List<String> _splittedTextList = [];
  List<String> get splittedTextList => _splittedTextList;

  getSizeFromBloc(GlobalKey pagekey) {
    _size = _dynamicSize.getSize(pagekey);
    print(_size);
  }

  getSplittedTextFromBloc(TextStyle textStyle, List<Paragraph> paragraph) {
    var text = paragraph.map((e) => e.element.innerHtml).toList();

    _splittedTextList =
        _splittedText.getSplittedText(_size!, textStyle, text.join());
  }

  void changeState(int currentIndex) {
    emit(currentIndex);
  }
}

class HorizontalChapterPage {
  HorizontalChapterPage(this.index, this.listString);
  
  final int index;
  final List<String> listString;
}
