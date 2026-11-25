class IkAlignmentSettingsStrings {
  static const immersion = '沉浸聆听';
  static const spatialDescription = '让左右声场更宽阔，为耳机听感增加空间层次。';
  static const spatialOff = '已关闭';
  static const strengthHint = '耳机模式 · 3D 环绕的效果强度';
  static const themeHint = '选择让眼睛舒服的界面';
  static String frequency(int hz) => switch (hz) {
    3600 => '3.6k Hz',
    14000 => '14k Hz',
    _ => '$hz Hz',
  };
  static String gain(double value) => '${value.toStringAsFixed(0)} dB';
}
