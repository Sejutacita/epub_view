import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class EpubBookChapterView extends StatelessWidget {
  EpubBookChapterView({
    required this.content,
  });

  final Widget content;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Container(
          child: content,
        ),
      );
}
