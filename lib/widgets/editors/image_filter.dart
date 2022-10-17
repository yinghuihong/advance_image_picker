import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

import '../../configs/image_picker_configs.dart';
import '../../utils/log_utils.dart';
import '../../utils/time_utils.dart';
import '../common/portrait_mode_mixin.dart';

/// Image filter widget.
class ImageFilter extends StatefulWidget {
  /// Default constructor for the image filter widget.
  const ImageFilter(
      {Key? key,
      required this.title,
      required this.file,
      this.configs,
      this.maxWidth = 1280,
      this.maxHeight = 720})
      : super(key: key);

  /// Input file object.
  final File file;

  /// Title for image edit widget.
  final String title;

  /// Max width.
  final int maxWidth;

  /// Max height.
  final int maxHeight;

  /// Configuration.
  final ImagePickerConfigs? configs;

  @override
  State<StatefulWidget> createState() => _ImageFilterState();
}

class _ImageFilterState extends State<ImageFilter>
    with PortraitStatefulModeMixin<ImageFilter> {
  final Map<String, List<int>?> _cachedFilters = {};
  final ListQueue<MapEntry<String, Future<List<int>?> Function()>>
      _queuedApplyFilterFuncList =
      ListQueue<MapEntry<String, Future<List<int>?> Function()>>();
  int _runningCount = 0;
  late Filter _filter;
  // late List<Filter> _filters;
  late Uint8List? _imageBytes;
  late Uint8List? _thumbnailImageBytes;
  late bool _loading;
  ImagePickerConfigs _configs = ImagePickerConfigs();

  @override
  void initState() {
    super.initState();
    if (widget.configs != null) _configs = widget.configs!;

    _loading = true;
    _filter = _presetFilters[0];

    Future.delayed(const Duration(milliseconds: 500), () async {
      await _loadImageData();
    });
  }

  @override
  void dispose() {
    _cachedFilters.clear();
    _queuedApplyFilterFuncList.clear();
    super.dispose();
  }

  Future<void> _loadImageData() async {
    _imageBytes = await widget.file.readAsBytes();
    _thumbnailImageBytes = await widget.file.readAsBytes();
    // _thumbnailImageBytes = await (await ImageUtils.compressResizeImage(
    //         widget.file.path,
    //         maxWidth: 100,
    //         maxHeight: 100))
    //     .readAsBytes();

    setState(() {
      _loading = false;
    });
  }

  Future<List<int>?> _getFilteredData(String key) async {
    if (_cachedFilters.containsKey(key)) {
      return _cachedFilters[key];
    } else {
      return Future.delayed(
          const Duration(milliseconds: 500), () => _getFilteredData(key));
    }
  }

  Future<void> _runApplyFilterProcess() async {
    while (_queuedApplyFilterFuncList.isNotEmpty) {
      if (!mounted) break;

      if (_runningCount > 2) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      LogUtils.log("_runningCount: ${_runningCount.toString()}");

      final func = _queuedApplyFilterFuncList.removeFirst();
      _runningCount++;
      final ret = await func.value.call();
      _cachedFilters[func.key] = ret;
      _runningCount--;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Use theme based AppBar colors if config values are not defined.
    // The logic is based on same approach that is used in AppBar SDK source.
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppBarTheme appBarTheme = AppBarTheme.of(context);
    final Color _appBarBackgroundColor = _configs.appBarBackgroundColor ??
        appBarTheme.backgroundColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.surface
            : colorScheme.primary);
    final Color _appBarTextColor = _configs.appBarTextColor ??
        appBarTheme.foregroundColor ??
        (colorScheme.brightness == Brightness.dark
            ? colorScheme.onSurface
            : colorScheme.onPrimary);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: CloseButton(
            color: _appBarTextColor
        ),
        title: Text(widget.title, style: TextStyle(color: _appBarTextColor)),
        backgroundColor: _appBarBackgroundColor,
        foregroundColor: _appBarTextColor,
        actions: <Widget>[
          if (_loading)
            Container()
          else
            IconButton(
              icon: Icon(Icons.check, color: _appBarTextColor),
              onPressed: () async {
                setState(() {
                  _loading = true;
                });
                final imageFile = await saveFilteredImage();
                if (!mounted) return;
                Navigator.pop(context, imageFile);
              },
            )
        ],
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: _loading
            ? const CupertinoActivityIndicator()
            : Column(
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      // padding: const EdgeInsets.all(8),
                      child: _buildFilteredWidget(_filter, _imageBytes!),
                    ),
                  ),
                  Container(
                    height: 150,
                    padding: const EdgeInsets.all(12),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _presetFilters.length,
                      itemBuilder: (BuildContext context, int index) {
                        return GestureDetector(
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            child: Column(
                              children: <Widget>[
                                SizedBox(
                                  width: 90,
                                  height: 75,
                                  child: _buildFilteredWidget(
                                      _presetFilters[index],
                                      _thumbnailImageBytes!,
                                      isThumbnail: true),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(_presetFilters[index].name,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                )
                              ],
                            ),
                          ),
                          onTap: () => setState(() {
                            _filter = _presetFilters[index];
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<File> saveFilteredImage() async {
    final dir = await path_provider.getTemporaryDirectory();
    final targetPath =
        "${dir.absolute.path}/temp_${TimeUtils.getTimeString(DateTime.now())}.jpg";
    final File imageFile = File(targetPath);

    // Run selected filter on output image
    final outputBytes = await _filter.apply(_imageBytes!);
    await imageFile.writeAsBytes(outputBytes!);
    return imageFile;
  }

  Widget _buildFilteredWidget(Filter filter, Uint8List imgBytes,
      {bool isThumbnail = false}) {
    final key = filter.name + (isThumbnail ? "thumbnail" : "");
    final data = _cachedFilters.containsKey(key) ? _cachedFilters[key] : null;
    final isSelected = filter.name == _filter.name;

    Widget createWidget(Uint8List? bytes) {
      if (isThumbnail) {
        return Container(
          decoration: BoxDecoration(
              color: Colors.grey,
              border: Border.all(
                  color: isSelected ? widget.configs!.appBarDoneButtonColor! : Colors.white, width: 3),
              borderRadius: const BorderRadius.all(Radius.circular(10))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(bytes!, fit: BoxFit.cover)),
        );
      } else {
        return Container(
          color: Colors.transparent,
          child: Image.memory(
            bytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        );
      }
    }

    if (data == null) {
      Future<Uint8List?> calcFunc() async {
        return filter.apply(imgBytes);
      }

      _queuedApplyFilterFuncList
          .add(MapEntry<String, Future<Uint8List?> Function()>(key, calcFunc));
      _runApplyFilterProcess();

      return FutureBuilder<List<int>?>(
        future: _getFilteredData(key),
        builder: (BuildContext context, AsyncSnapshot<List<int>?> snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.done:
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              return createWidget(snapshot.data as Uint8List?);
            default:
              return const CupertinoActivityIndicator();
          }
        },
      );
    } else {
      return createWidget(data as Uint8List?);
    }
  }

  // https://developer.android.google.cn/reference/android/graphics/ColorMatrix.html
  static const List<Filter> _presetFilters = <Filter>[
    Filter(name: "no filter"),
    Filter(name: "invert", matrix: <double>[
      -1, 0, 0, 0, 255, // R
      0, -1, 0, 0, 255,
      0, 0, -1, 0, 255,
      0, 0, 0, 1, 0
    ]),
    Filter(name: "lighten", matrix: <double>[
      1.5, 0, 0, 0, 0, // R
      0, 1.5, 0, 0, 0, // G
      0, 0, 1.5, 0, 0, // B
      0, 0, 0, 1, 0 // A
    ]),
    Filter(name: "darken", matrix: <double>[
      .5,
      0,
      0,
      0,
      0,
      0,
      .5,
      0,
      0,
      0,
      0,
      0,
      .5,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "gray on light", matrix: <double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "old times", matrix: <double>[
      1,
      0,
      0,
      0,
      0,
      -0.4,
      1.3,
      -0.4,
      .2,
      -0.1,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "sepia", matrix: <double>[
      0.393,
      0.769,
      0.189,
      0,
      0,
      0.349,
      0.686,
      0.168,
      0,
      0,
      0.272,
      0.534,
      0.131,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "greyscale", matrix: <double>[
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0.2126,
      0.7152,
      0.0722,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "vintage", matrix: <double>[
      0.9,
      0.5,
      0.1,
      0,
      0,
      0.3,
      0.8,
      0.1,
      0,
      0,
      0.2,
      0.3,
      0.5,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "filter 1", matrix: <double>[
      0.4,
      0.4,
      -0.3,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1.2,
      0,
      0,
      -1.2,
      0.6,
      0.7,
      1,
      0
    ]),
    Filter(name: "filter 2", matrix: <double>[
      1,
      0,
      0.2,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "filter 3", matrix: <double>[
      0.8,
      0.5,
      0,
      0,
      0,
      0,
      1.1,
      0,
      0,
      0,
      0,
      0.2,
      1.1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "filter 4", matrix: <double>[
      1.1,
      0,
      0,
      0,
      0,
      0.2,
      1,
      -0.4,
      0,
      0,
      -0.1,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "filter 5", matrix: <double>[
      1.2,
      0.1,
      0.5,
      0,
      0,
      0.1,
      1,
      0.05,
      0,
      0,
      0,
      0.1,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "elim blue", matrix: <double>[
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      -2,
      1,
      0
    ]),
    Filter(name: "no g red", matrix: <double>[
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "no g magenta", matrix: <double>[
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "lime", matrix: <double>[
      1,
      0,
      0,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      .5,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "purple", matrix: <double>[
      1,
      -0.2,
      0,
      0,
      0,
      0,
      1,
      0,
      -0.1,
      0,
      0,
      1.2,
      1,
      .1,
      0,
      0,
      0,
      1.7,
      1,
      0
    ]),
    Filter(name: "yellow", matrix: <double>[
      1,
      0,
      0,
      0,
      0,
      -0.2,
      1,
      .3,
      .1,
      0,
      -0.1,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]),
    Filter(name: "cyan", matrix: <double>[
      1,
      0,
      0,
      1.9,
      -2.2,
      0,
      1,
      0,
      0,
      .3,
      0,
      0,
      1,
      0,
      .5,
      0,
      0,
      0,
      1,
      .2
    ]),
    // Filter(name: "invert", matrix: <double>[-1, 0, 0, 0,
    // 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]),
  ];
}

/// Hold the name of an image filter and its Filter Matrix values.
class Filter extends Object {
  /// Default constructor for Filter.
  const Filter({required this.name, this.matrix = defaultColorMatrix});

  /// Name of the filter.
  final String name;

  /// Image filter matrix values.
  final List<double> matrix;

  /// Apply this filter to the image.
  Future<Uint8List?> apply(Uint8List pixels) async {
    final ImageEditorOption option = ImageEditorOption();
    option.addOption(ColorOption(matrix: matrix));
    return ImageEditor.editImage(image: pixels, imageEditorOption: option);
  }
}
