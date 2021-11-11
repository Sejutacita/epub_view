import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view/src/ui/horizontal_view/horizontal_page.dart';
import 'package:epubx/epubx.dart' hide Image;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:rxdart/rxdart.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:csslib/parser.dart' as css;
import 'epub_cfi/generator.dart';
import 'epub_cfi/interpreter.dart';
import 'epub_cfi/parser.dart';

export 'package:epubx/epubx.dart' hide Image;

part 'epub_cfi_reader.dart';
part 'epub_controller.dart';
part 'epub_data.dart';
part 'epub_parser.dart';

const MIN_TRAILING_EDGE = 0.55;
const MIN_LEADING_EDGE = -0.05;

const _defaultTextStyle = TextStyle(
  height: 1.25,
  fontSize: 16,
);

typedef ChaptersBuilder = Widget Function(
  BuildContext context,
  List<EpubChapter> chapters,
  List<Paragraph> paragraphs,
  int index,
);

typedef ExternalLinkPressed = void Function(String href);

class EpubView extends StatefulWidget {
  const EpubView({
    required this.controller,
    this.itemBuilder,
    this.onExternalLinkPressed,
    this.loaderSwitchDuration,
    this.loader,
    this.errorBuilder,
    this.dividerBuilder,
    this.onChange,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.chapterPadding = const EdgeInsets.all(8),
    this.paragraphPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.textStyle = _defaultTextStyle,
    this.isHorizontalView = false,
    this.initialIndex = 0,
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;

  /// Show document loading error message inside [EpubView]
  final Widget Function(Exception? error)? errorBuilder;
  final Widget Function(EpubChapter value)? dividerBuilder;
  final void Function(EpubChapterViewValue? value)? onChange;

  /// Called when a document is loaded
  final void Function(EpubBook? document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;
  final Duration? loaderSwitchDuration;
  final Widget? loader;
  final EdgeInsetsGeometry chapterPadding;
  final EdgeInsetsGeometry paragraphPadding;
  final ChaptersBuilder? itemBuilder;
  final TextStyle textStyle;
  final bool isHorizontalView;
  final int initialIndex;

  @override
  _EpubViewState createState() => _EpubViewState();
}

class _EpubViewState extends State<EpubView> {
  _EpubViewLoadingState _loadingState = _EpubViewLoadingState.loading;
  Exception? _loadingError;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionListener;
  List<EpubChapter> _chapters = [];
  List<Paragraph> _paragraphs = [];
  EpubCfiReader? _epubCfiReader;
  EpubChapterViewValue? _currentValue;
  bool _initialized = false;

  final List<int> _chapterIndexes = [];
  final BehaviorSubject<EpubChapterViewValue?> _actualChapter =
      BehaviorSubject();
  final BehaviorSubject<bool> _bookLoaded = BehaviorSubject();

  PageController? _horizontalPageController;
  int _activeChapterIndex = 0;

  @override
  void initState() {
    _activeChapterIndex = widget.initialIndex;
    _itemScrollController = ItemScrollController();
    _itemPositionListener = ItemPositionsListener.create();
    _horizontalPageController =
        PageController(initialPage: _activeChapterIndex);
    widget.controller._attach(this);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionListener!.itemPositions
        .removeListener(_customVerticalChangeScrollListener);
    _horizontalPageController?.dispose();
    _actualChapter.close();
    widget.controller._detach();
    _bookLoaded.close();
    super.dispose();
  }

  Future<bool> _init() async {
    if (_initialized) {
      return true;
    }
    _chapters = parseChapters(widget.controller._document!);
    final parseParagraphsResult =
        parseParagraphs(_chapters, widget.controller._document!.Content);
    _paragraphs = parseParagraphsResult.flatParagraphs;
    _chapterIndexes.addAll(parseParagraphsResult.chapterIndexes);

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: widget.controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );
    // _itemPositionListener!.itemPositions.addListener(_changeListener);
    _itemPositionListener!.itemPositions
        .addListener(_customVerticalChangeScrollListener);
    _initialized = true;
    _bookLoaded.sink.add(true);

    return true;
  }

  void _customVerticalChangeScrollListener() {
    final position = _itemPositionListener!.itemPositions.value.first;
    _activeChapterIndex = position.index;
    _currentValue = EpubChapterViewValue(
      chapter: _chapters[position.index],
      chapterNumber: position.index + 1,
      paragraphNumber: 0,
      position: position,
    );

    if (_itemPositionListener!.itemPositions.value.last.index >=
        _chapters.length - 1) {
      _currentValue = EpubChapterViewValue(
        chapter: _chapters[position.index],
        chapterNumber:
            _itemPositionListener!.itemPositions.value.last.index + 1,
        paragraphNumber: 0,
        position: position,
      );
    }

    _actualChapter.sink.add(_currentValue);
    widget.onChange?.call(_currentValue);
  }

  void _gotoEpubCfi(
    String? epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubCfiReader?.epubCfi = epubCfi;
    final index = _epubCfiReader?.paragraphIndexByCfiFragment;

    if (index == null) {
      return null;
    }

    _itemScrollController?.scrollTo(
      index: index,
      duration: duration,
      alignment: alignment,
      curve: curve,
    );
  }

  void _onLinkPressed(String href, void Function(String href)? openExternal) {
    if (href.contains('://')) {
      openExternal?.call(href);
      return;
    }

    // Chapter01.xhtml#ph1_1 -> [ph1_1, Chapter01.xhtml] || [ph1_1]
    String? hrefIdRef;
    String? hrefFileName;

    if (href.contains('#')) {
      final dividedHref = href.split('#');
      if (dividedHref.length == 1) {
        hrefIdRef = href;
      } else {
        hrefFileName = dividedHref[0];
        hrefIdRef = dividedHref[1];
      }
    } else {
      hrefFileName = href;
    }

    if (hrefIdRef == null) {
      final chapter = _chapterByFileName(hrefFileName);
      if (chapter != null) {
        final cfi = _epubCfiReader?.generateCfiChapter(
          book: widget.controller._document,
          chapter: chapter,
          additional: ['/4/2'],
        );

        _gotoEpubCfi(cfi);
      }
      return;
    } else {
      final paragraph = _paragraphByIdRef(hrefIdRef);
      final chapter =
          paragraph != null ? _chapters[paragraph.chapterIndex] : null;

      if (chapter != null && paragraph != null) {
        final paragraphIndex =
            _epubCfiReader?._getParagraphIndexByElement(paragraph.element);
        final cfi = _epubCfiReader?.generateCfi(
          book: widget.controller._document,
          chapter: chapter,
          paragraphIndex: paragraphIndex,
        );

        _gotoEpubCfi(cfi);
      }

      return;
    }
  }

  Paragraph? _paragraphByIdRef(String idRef) =>
      _paragraphs.firstWhereOrNull((paragraph) {
        if (paragraph.element.id == idRef) {
          return true;
        }

        return paragraph.element.children.isNotEmpty &&
            paragraph.element.children[0].id == idRef;
      });

  EpubChapter? _chapterByFileName(String? fileName) =>
      _chapters.firstWhereOrNull((chapter) {
        if (fileName != null) {
          if (chapter.ContentFileName!.contains(fileName)) {
            return true;
          } else {
            return false;
          }
        }
        return false;
      });

  int _getAbsParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    int posIndex = positionIndex;
    if (trailingEdge != null &&
        leadingEdge != null &&
        trailingEdge < MIN_TRAILING_EDGE &&
        leadingEdge < MIN_LEADING_EDGE) {
      posIndex += 1;
    }

    return posIndex;
  }

  void _changeLoadingState(_EpubViewLoadingState state) {
    if (state == _EpubViewLoadingState.success) {
      widget.onDocumentLoaded?.call(widget.controller._document);
    } else if (state == _EpubViewLoadingState.error) {
      widget.onDocumentError?.call(_loadingError);
    }
    setState(() {
      _loadingState = state;
    });
  }

  Widget _defaultItemBuilder(int index) {
    if (_paragraphs.isEmpty) {
      return Container();
    }

    // final chapterIndex = _getChapterIndexBy(positionIndex: index);

    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          htmlContent(_chapters[index].HtmlContent ?? ''),
        ],
      ),
    );
  }

  ///This function is to search if there are [key] style in the CSS files and return the block
  String getCSSBlock(String key) {
    String styles = '';
    try {
      String? styleSheet =
          widget.controller._document!.Content?.Css?['stylesheet.css']?.Content;
      List<String> styleSheets = styleSheet?.split('}\n') ?? [];
      var styleSheetParsed = css.parse(styleSheet);
      styleSheetParsed.topLevels.forEach((node) {
        if (node.toDebugString().contains(key)) {
          styleSheets.forEach((element) {
            if (element.contains(node.span?.text ?? '')) {
              styles += element;
              styles += '}';
            }
          });
        }
      });
    } catch (_) {}

    return styles;
  }

  ///This function is to search if there are [key] and [className] style in the CSS files and return the block
  String getCSSBlockFromKeyAndClassName(String key, String className) {
    String styles = '';
    try {
      String? styleSheet =
          widget.controller._document!.Content?.Css?['stylesheet.css']?.Content;
      List<String> styleSheets = styleSheet?.split('}\n') ?? [];
      var styleSheetParsed = css.parse(styleSheet);
      styleSheetParsed.topLevels.forEach((node) {
        if (node.toDebugString().contains(key) &&
            node.toDebugString().contains(className)) {
          styleSheets.forEach((element) {
            if (element.contains(node.span?.text ?? '')) {
              styles += element;
              styles += '}';
            }
          });
        }
      });
    } catch (_) {}

    return styles;
  }

  Widget htmlContent(String htmlString) {
    final TextStyle epubTextStyle = widget.textStyle.copyWith(
      fontFamily: 'Helvetica',
    );

    return Html(
      data: htmlString
          .replaceAll(
            '<link rel="stylesheet" type="text/css" href="stylesheet.css"/>',
            '<style>${getCSSBlock('italic')}</style>',
          )
          .replaceAll('display: block;', ''),
      onLinkTap: (href, _, __, ___) => _onLinkPressed(
        href ?? '',
        widget.onExternalLinkPressed,
      ),
      style: {
        'html': Style(
          padding: widget.paragraphPadding as EdgeInsets?,
          textAlign: TextAlign.start,
        ).merge(Style.fromTextStyle(epubTextStyle)),
        'h1': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14) + 2,
            ),
          ),
        ),
        'h2': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14) + 1,
            ),
          ),
        ),
        'li': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          display: Display.LIST_ITEM,
          listStylePosition: ListStylePosition.INSIDE,
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14),
            ),
          ),
        ),
        'ol': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14),
            ),
          ),
        ),
        'p': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.only(top: 4),
          padding: EdgeInsets.only(bottom: 0.6),
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14),
            ),
          ),
        ),
        'span': Style(
          textAlign: TextAlign.left,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
        ).merge(
          Style.fromTextStyle(
            epubTextStyle.copyWith(
              fontSize: (epubTextStyle.fontSize ?? 14),
            ),
          ),
        ),
      },
      shrinkWrap: true,
      customRender: {
        'img': (context, child) {
          final url =
              context.tree.element!.attributes['src']!.replaceAll('../', '');
          return Image(
            image: MemoryImage(
              Uint8List.fromList(
                widget.controller._document!.Content!.Images![url]!.Content!,
              ),
            ),
          );
        },
        'h1': (RenderContext context, Widget child) {
          if (context.tree.children.isNotEmpty) {
            String text =
                context.tree.children.first.element?.text.toString() ?? '';

            if ((context.tree.children.first.toString() == '\" \"' ||
                    context.tree.children.first.toString() == '\"\\n\"') &&
                text.length <= 4) {
              return SizedBox();
            }

            if (context.tree.children.length > 1) {
              ///If [isMultipleText] and the [text] length is more than 4 character, then it means that it is have more than one text
              bool isMultipleText = context.tree.children
                  .every((child) => (child.element?.text.length ?? 0) > 4);
              if (isMultipleText) {
                return null;
              }
            }

            return Text(
              context.tree.children.first.element?.text.replaceAll('\n', '') ??
                  '',
              style: epubTextStyle.copyWith(
                fontFamily: 'Helvetica',
                fontWeight: FontWeight.bold,
                fontSize: (epubTextStyle.fontSize ?? 14) + 2,
              ),
            );
          }

          return null;
        },
        'p': (RenderContext context, Widget child) {
          bool isEmptyText = false;

          if (context.tree.children.isNotEmpty) {
            isEmptyText = context.tree.children.first
                    .toString()
                    .replaceAll('\"', '')
                    .length ==
                1;
          }

          if (isEmptyText) return SizedBox();

          return null;
        },
        "ol": (RenderContext context, Widget child) {
          dom.Element? element = context.tree.element;
          return _customOrderedListItem(element);
        },
      },
    );
  }

  Widget? _customOrderedListItem(dom.Element? element) {
    final TextStyle epubTextStyle = widget.textStyle.copyWith(
      fontFamily: 'Helvetica',
    );

    List<dom.Element>? listIttemElement =
        parse(element?.innerHtml ?? '').body?.children;
    if (listIttemElement != null && listIttemElement != []) {
      if (listIttemElement.length == 1) {
        final bool isElementHaveBoldStyle = (getCSSBlockFromKeyAndClassName(
                    'bold', listIttemElement.first.className) !=
                '' ||
            listIttemElement.first.outerHtml.contains('</b>'));
        final bool isElementHaveItalicStyle = (getCSSBlockFromKeyAndClassName(
                    'italic', listIttemElement.first.className) !=
                '' ||
            listIttemElement.first.outerHtml.contains('</i>'));

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: listIttemElement
                .mapIndexed(
                  (int index, dom.Element element) => Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
                    child: Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text(
                        "${element.attributes['value'] ?? (index + 1)}. ${element.text}",
                        style: epubTextStyle.copyWith(
                          fontWeight: isElementHaveBoldStyle
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: isElementHaveItalicStyle
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: HtmlWidget(
              '${element?.outerHtml.replaceAll('>&nbsp;', '>')}',
              textStyle: epubTextStyle.copyWith(
                letterSpacing: 0.42,
              ),
              customStylesBuilder: (element) {
                final bool isElementHaveItalicStyle =
                    getCSSBlockFromKeyAndClassName(
                            'italic', element.className) !=
                        '';
                final bool isElementHaveBoldStyle =
                    getCSSBlockFromKeyAndClassName('bold', element.className) !=
                        '';

                Map<String, String> _tempMap = {
                  'margin': '0',
                  'padding': '0',
                };
                if (isElementHaveItalicStyle) {
                  _tempMap['font-style'] = 'italic';
                }
                if (isElementHaveBoldStyle) {
                  _tempMap['font-weight'] = 'bold';
                }

                return _tempMap;
              },
            ),
          ),
        );
      }
    } else {
      return null;
    }
  }

  Widget _buildLoaded() {
    Widget _buildItem(BuildContext context, int index) =>
        _defaultItemBuilder(index);

    if (widget.isHorizontalView) {
      // this need to call to update the chapter value first
      _horizontalPageChangedListener(_activeChapterIndex);
      _horizontalPageController?.dispose();
      _horizontalPageController =
          PageController(initialPage: _activeChapterIndex);

      return PageView.builder(
        itemCount: _chapters.length,
        controller: _horizontalPageController,
        onPageChanged: _horizontalPageChangedListener,
        itemBuilder: (BuildContext context, int index) {
          final chapter = _chapters[index];
          return EpubBookChapterView(
            content: htmlContent(chapter.HtmlContent ?? ''),
          );
        },
      );
    }

    return ScrollablePositionedList.builder(
      initialScrollIndex:
          _epubCfiReader!.paragraphIndexByCfiFragment ?? _activeChapterIndex,
      itemCount: _chapters.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionListener,
      itemBuilder: _buildItem,
    );
  }

  void _horizontalPageChangedListener(int index) {
    _activeChapterIndex = index;
    _currentValue = EpubChapterViewValue(
      chapter: _chapters[index],
      chapterNumber: index + 1,
      paragraphNumber: 0,
      position:
          ItemPosition(index: index, itemLeadingEdge: 0, itemTrailingEdge: 0),
    );
    _actualChapter.sink.add(_currentValue);
    widget.onChange?.call(_currentValue);
  }

  @override
  Widget build(BuildContext context) {
    Widget? content;

    switch (_loadingState) {
      case _EpubViewLoadingState.loading:
        content = KeyedSubtree(
          key: Key('$runtimeType.root.loading'),
          child: widget.loader ?? SizedBox(),
        );
        break;
      case _EpubViewLoadingState.error:
        content = KeyedSubtree(
          key: Key('$runtimeType.root.error'),
          child: Padding(
            padding: EdgeInsets.all(32),
            child: widget.errorBuilder?.call(_loadingError) ??
                Center(child: Text(_loadingError.toString())),
          ),
        );
        break;
      case _EpubViewLoadingState.success:
        content = KeyedSubtree(
          key: Key('$runtimeType.root.success'),
          child: _buildLoaded(),
        );
        break;
    }

    return AnimatedSwitcher(
      duration: widget.loaderSwitchDuration ?? Duration(milliseconds: 500),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: content,
    );
  }
}

enum _EpubViewLoadingState {
  loading,
  error,
  success,
}
