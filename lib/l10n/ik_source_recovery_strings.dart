abstract final class IkSourceRecoveryStrings {
  static const dnsFailed = '音源地址无法解析，请检查网络或更换音源';
  static const connectionFailed = '音源连接失败';
  static const unavailable = '当前启用且兼容的候选均未能播放';
  static const interrupted = '当前音源请求未完成，请查看详情后重试';
  static String budgetUsed(int attempted, int remaining) =>
      '已尝试 $attempted 个候选，剩余 $remaining 个；可继续尝试';
}
