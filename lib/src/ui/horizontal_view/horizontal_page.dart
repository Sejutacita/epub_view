import 'package:epub_view/epub_view.dart';
import 'package:epub_view/src/ui/horizontal_view/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_html/flutter_html.dart';

class HorizontalPageView extends StatelessWidget {
  const HorizontalPageView({
    Key? key,
    required this.paragraph,
    required this.onPageChanged,
    this.style,
  }) : super(key: key);

  final List<Paragraph> paragraph;
  final Function(int) onPageChanged;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PageControlBloc(),
      child: HorizontalPage(
        style: style ?? TextStyle(),
        paragraph: paragraph,
        onPageChanged: onPageChanged,
      ),
    );
  }
}

class HorizontalPage extends StatefulWidget {
  const HorizontalPage({
    Key? key,
    required this.style,
    required this.paragraph,
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
  Widget build(BuildContext context) {
    return Expanded(
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
          itemBuilder: (context, index) {
            return Html(
              data: controlBloc?.splittedTextList[index],
              shrinkWrap: true,
              style: {
                'html': Style(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                ).merge(Style.fromTextStyle(widget.style)),
              },
            );
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 8),
            //   child: Text(
            //     controlBloc.splittedTextList[index],
            //     style: widget.style,
            //   ),
            // );
          },
        ),
      ),
    );
  }
}
