import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/ui/horizontal_view/dynamic_size.dart';
import 'package:epub_view/src/ui/horizontal_view/splitted_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PageControlBloc extends Cubit<int> {
  PageControlBloc() : super(0);

  final DynamicSize _dynamicSize = DynamicSizeImpl();
  final SplittedText _splittedText = SplittedTextImpl();
  Size? _size;
  List<String> _splittedTextList = [];
  List<String> get splittedTextList => _splittedTextList;

  void getSizeFromBloc(GlobalKey pagekey) {
    _size = _dynamicSize.getSize(pagekey);
    print(_size);
  }

  void getSplittedTextFromBloc(TextStyle textStyle, List<Paragraph> paragraph) {
    final text = paragraph.map((e) => e.element.innerHtml).toList();

    _splittedTextList =
        _splittedText.getSplittedText(_size!, textStyle, text.join());
  }

  void changeState(int currentIndex) {
    emit(currentIndex);
  }
}

class HorizontalChapterPage {
  HorizontalChapterPage(this.index, this.htmlText);

  final int index;
  final String htmlText;
}

class DisplayedHtml {
  DisplayedHtml(this.startIndex, this.endIndex, this.page, this.htmlText);

  final int startIndex;
  final int endIndex;
  final int page;
  final List<String> htmlText;
}
