import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';

class EpubBookChapterView extends StatelessWidget {
  EpubBookChapterView(
      {required this.chapter, required this.style, required this.content});

  final EpubChapter chapter;
  final TextStyle style;
  final Widget content;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.only(
            right: 8,
            left: 8,
          ),
          child: content,
        ),
      );
}
