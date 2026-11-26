import 'package:flutter/material.dart';

import '../../l10n/ik_lyrics_style_strings.dart';
import 'ik_controls.dart';

/// 播放详情和桌面歌词共用的内嵌样式编辑，不弹出设置对话框。
class IkLyricsStylePanel extends StatelessWidget {
  const IkLyricsStylePanel({
    super.key,
    required this.title,
    required this.systemFonts,
    required this.fontFamily,
    required this.fontSize,
    required this.backgroundColor,
    required this.currentLineColor,
    required this.otherLineColor,
    required this.shadowOpacity,
    required this.onFontFamily,
    required this.onFontSize,
    required this.onBackgroundColor,
    required this.onCurrentLineColor,
    required this.onOtherLineColor,
    required this.onShadowOpacity,
    this.onReset,
    this.onClose,
    this.backgroundOpacity,
    this.onBackgroundOpacity,
    this.busy = false,
    this.issue,
  });

  final String title;
  final List<String> systemFonts;
  final String? fontFamily;
  final double fontSize, shadowOpacity;
  final Color backgroundColor, currentLineColor, otherLineColor;
  final ValueChanged<String?> onFontFamily;
  final ValueChanged<double> onFontSize, onShadowOpacity;
  final ValueChanged<Color> onBackgroundColor,
      onCurrentLineColor,
      onOtherLineColor;
  final VoidCallback? onReset, onClose;
  final double? backgroundOpacity;
  final ValueChanged<double>? onBackgroundOpacity;
  final bool busy;
  final String? issue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: IkLyricsStyleStrings.close,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            IkSelect<String>(
              label: IkLyricsStyleStrings.font,
              value: fontFamily ?? '',
              items: {
                '': IkLyricsStyleStrings.inheritFont,
                for (final font in {?fontFamily, ...systemFonts}) font: font,
              },
              onChanged: (font) => onFontFamily(font.isEmpty ? null : font),
              enabled: !busy,
              alignToDesign: true,
            ),
            const SizedBox(height: 6),
            Text(
              IkLyricsStyleStrings.savedFonts,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _range(
              IkLyricsStyleStrings.fontSize,
              fontSize,
              14,
              48,
              onFontSize,
              suffix: ' px',
            ),
            _color(
              context,
              IkLyricsStyleStrings.background,
              backgroundColor,
              onBackgroundColor,
            ),
            _color(
              context,
              IkLyricsStyleStrings.currentLine,
              currentLineColor,
              onCurrentLineColor,
            ),
            _color(
              context,
              IkLyricsStyleStrings.otherLines,
              otherLineColor,
              onOtherLineColor,
            ),
            if (backgroundOpacity != null && onBackgroundOpacity != null)
              _range(
                IkLyricsStyleStrings.opacity,
                backgroundOpacity! * 100,
                0,
                100,
                (value) => onBackgroundOpacity!(value / 100),
                suffix: '%',
              ),
            _range(
              IkLyricsStyleStrings.shadow,
              shadowOpacity * 100,
              0,
              100,
              (value) => onShadowOpacity(value / 100),
              suffix: '%',
            ),
            if (issue != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  issue!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ),
            if (onReset != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : onReset,
                  child: const Text(IkLyricsStyleStrings.reset),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _range(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change, {
    required String suffix,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${value.round()}$suffix'),
          ],
        ),
        _IkStyleSlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          enabled: !busy,
          onCommit: change,
        ),
      ],
    ),
  );

  Widget _color(
    BuildContext context,
    String label,
    Color value,
    ValueChanged<Color> change,
  ) {
    const palette = [
      Color(0xff11877f),
      Color(0xff78d9c5),
      Color(0xfff1f5f4),
      Colors.white,
      Color(0xff172a32),
      Color(0xff71858e),
      Color(0xfff2cc75),
      Color(0xff80b8f0),
      Color(0xffe9b5c6),
      Color(0xffa67435),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final color in {value.withValues(alpha: 1), ...palette})
                Semantics(
                  label:
                      '$label #${color.toARGB32().toRadixString(16).substring(2)}',
                  selected: value.withValues(alpha: 1) == color,
                  button: true,
                  child: InkWell(
                    onTap: busy ? null : () => change(color),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: value.withValues(alpha: 1) == color
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: value.withValues(alpha: 1) == color ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IkStyleSlider extends StatefulWidget {
  const _IkStyleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onCommit,
  });
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onCommit;
  @override
  State<_IkStyleSlider> createState() => _IkStyleSliderState();
}

class _IkStyleSliderState extends State<_IkStyleSlider> {
  double? _draft;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Slider(
      value: (_draft ?? widget.value).clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: (widget.max - widget.min).round(),
      label: (_draft ?? widget.value).round().toString(),
      onChanged: widget.enabled
          ? (value) => setState(() => _draft = value)
          : null,
      onChangeEnd: widget.enabled
          ? (value) {
              setState(() => _draft = null);
              widget.onCommit(value);
            }
          : null,
    ),
  );
}
