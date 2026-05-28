/**
 * 错误码定义
 * 
 * 定义了数据库操作的标准错误码
 */
module dunqlite.oop.error;

/**
 * 错误码枚举
 * 
 * 定义所有可能的操作结果状态
 */
enum ErrorCode {
    OK = 0,          /// 操作成功
    NOT_FOUND = -1,  /// 未找到
    NO_MEMORY = -2,  /// 内存不足
    INVALID = -3,    /// 无效操作
    IO_ERROR = -4,   /// IO错误
    LIMIT = -5       /// 达到限制
}
