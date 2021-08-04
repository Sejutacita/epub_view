import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/ui/horizontal_view/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_html/flutter_html.dart';

class HorizontalPageView extends StatelessWidget {
  const HorizontalPageView({
    required this.paragraph,
    required this.onPageChanged,
    this.style,
    Key? key,
  }) : super(key: key);

  final List<Paragraph> paragraph;
  final Function(int) onPageChanged;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => PageControlBloc(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HorizontalPage(
            style: style ?? TextStyle(),
            paragraph: paragraph,
            onPageChanged: onPageChanged,
          ),
        ),
      );
}

class EpubBookChapterView extends StatelessWidget {
  EpubBookChapterView({required this.chapter, required this.style});

  final EpubChapter chapter;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Container(
          margin: EdgeInsets.only(
            right: 8,
            left: 8,
          ),
          child: Html(
            data: chapter.HtmlContent,
            style: {
              'html': Style(
                padding: EdgeInsets.symmetric(horizontal: 8),
              ).merge(Style.fromTextStyle(style)),
            },
          ),
        ),
      );
}

class HorizontalPage extends StatefulWidget {
  const HorizontalPage({
    required this.style,
    required this.paragraph,
    Key? key,
    this.onPageChanged,
  }) : super(key: key);

  final TextStyle style;
  final List<Paragraph> paragraph;
  final Function(int)? onPageChanged;

  @override
  _HorizontalPageState createState() => _HorizontalPageState();
}

class _HorizontalPageState extends State<HorizontalPage> {
  final GlobalKey pageKey = GlobalKey();

  final PageController _pageController = PageController();
  static PageControlBloc? controlBloc;

  @override
  void initState() {
    controlBloc = BlocProvider.of<PageControlBloc>(context);
    WidgetsBinding.instance!.addPostFrameCallback((_) {
      controlBloc?.getSizeFromBloc(pageKey);
      controlBloc?.getSplittedTextFromBloc(widget.style, widget.paragraph);
      setState(() {});
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          key: pageKey,
          // child: PageTurn(
          //   backgroundColor: widget.state.pageColor,
          //   children: controlBloc.splittedTextList.map((e) {
          //     return Text(e, style: widget.style);
          //   }).toList(),
          // ),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (val) {
              controlBloc?.changeState(val);
            },
            itemCount: controlBloc?.splittedTextList.length,
            itemBuilder: (context, index) => Html(
              data: controlBloc?.splittedTextList[index],
              shrinkWrap: true,
              style: {
                'html': Style(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ).merge(Style.fromTextStyle(widget.style)),
              },
            ),
          ),
        ),
      );
}
