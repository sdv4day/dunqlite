/**
 * WAL (Write-Ahead Logging) 实现
 * 
 * 提供崩溃恢复保护：
 * - 写入前先记录操作到日志
 * - 崩溃后重放日志恢复数据
 */
module dunqlite.oop.wal;

import std.stdio : File;
import std.conv : text;
import std.file : exists, remove, rename;

/**
 * WAL 操作类型
 */
enum WalOp : ubyte {
    PUT = 1,        /// 写入操作
    REMOVE = 2,     /// 删除操作
    CHECKPOINT = 3, /// 检查点标记
}

/**
 * WAL 记录头
 */
struct WalHeader {
    WalOp op;           /// 操作类型
    uint keyLen;        /// 键长度
    uint valLen;        /// 值长度（仅 PUT 使用）
    uint checksum;      /// 简单校验和
}

/**
 * WAL 管理器
 */
class Wal {
    private string walPath_;
    private string dbPath_;
    private File walFile_;
    private bool isOpen_ = false;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   dbPath = 数据库文件路径
     */
    this(string dbPath) {
        dbPath_ = dbPath;
        walPath_ = dbPath ~ ".wal";
    }
    
    ~this() {
        close();
    }
    
    /**
     * 打开 WAL 文件
     * 
     * 返回：
     *   是否成功
     */
    bool open() {
        if (isOpen_) return true;
        
        try {
            walFile_ = File(walPath_, "ab"); // 追加模式
            isOpen_ = true;
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 关闭 WAL 文件
     */
    void close() {
        if (!isOpen_) return;
        
        try {
            walFile_.flush();
            walFile_.close();
        } catch (Exception e) {
        }
        isOpen_ = false;
    }
    
    /**
     * 计算 CRC32 校验和（简化版）
     */
    private uint checksum(const(void)* data, size_t len) {
        uint crc = 0xFFFFFFFF;
        auto bytes = cast(const(ubyte)*)data;
        for (size_t i = 0; i < len; i++) {
            crc ^= bytes[i];
            for (int j = 0; j < 8; j++) {
                if (crc & 1)
                    crc = (crc >> 1) ^ 0xEDB88320;
                else
                    crc >>= 1;
            }
        }
        return ~crc;
    }
    
    /**
     * 记录 PUT 操作
     */
    bool logPut(const(void)* key, uint keyLen, const(void)* value, uint valLen) {
        if (!isOpen_) return false;
        
        WalHeader hdr;
        hdr.op = WalOp.PUT;
        hdr.keyLen = keyLen;
        hdr.valLen = valLen;
        
        // 计算校验和
        uint keyCrc = checksum(key, keyLen);
        uint valCrc = checksum(value, valLen);
        hdr.checksum = keyCrc ^ valCrc;
        
        try {
            // 写入头
            walFile_.rawWrite((cast(ubyte*)&hdr)[0 .. WalHeader.sizeof]);
            // 写入键
            walFile_.rawWrite((cast(const(ubyte)*)key)[0 .. keyLen]);
            // 写入值
            walFile_.rawWrite((cast(const(ubyte)*)value)[0 .. valLen]);
            // 立即刷盘
            walFile_.flush();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 记录 REMOVE 操作
     */
    bool logRemove(const(void)* key, uint keyLen) {
        if (!isOpen_) return false;
        
        WalHeader hdr;
        hdr.op = WalOp.REMOVE;
        hdr.keyLen = keyLen;
        hdr.valLen = 0;
        hdr.checksum = checksum(key, keyLen);
        
        try {
            walFile_.rawWrite((cast(ubyte*)&hdr)[0 .. WalHeader.sizeof]);
            walFile_.rawWrite((cast(const(ubyte)*)key)[0 .. keyLen]);
            walFile_.flush();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 记录检查点（表示数据已刷入主文件）
     */
    bool logCheckpoint() {
        if (!isOpen_) return false;
        
        WalHeader hdr;
        hdr.op = WalOp.CHECKPOINT;
        hdr.keyLen = 0;
        hdr.valLen = 0;
        hdr.checksum = 0;
        
        try {
            walFile_.rawWrite((cast(ubyte*)&hdr)[0 .. WalHeader.sizeof]);
            walFile_.flush();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * 检查是否存在 WAL 日志
     */
    bool exists() {
        return .exists(walPath_);
    }
    
    /**
     * 重放 WAL 日志
     * 
     * 参数：
     *   onPut = 处理 PUT 操作的回调
     *   onRemove = 处理 REMOVE 操作的回调
     * 
     * 返回：
     *   是否成功
     */
    bool replay(
        bool delegate(const(void)* key, uint keyLen, const(void)* value, uint valLen) onPut,
        bool delegate(const(void)* key, uint keyLen) onRemove
    ) {
        if (!.exists(walPath_)) return true;
        
        File f;
        try {
            f = File(walPath_, "rb");
        } catch (Exception e) {
            return false;
        }
        
        scope(exit) f.close();
        
        // 查找最后一个检查点
        long lastCheckpoint = -1;
        while (true) {
            long pos = f.tell();
            WalHeader hdr;
            auto read = f.rawRead((cast(ubyte*)&hdr)[0 .. WalHeader.sizeof]);
            if (read.length != WalHeader.sizeof) break;
            
            if (hdr.op == WalOp.CHECKPOINT) {
                lastCheckpoint = pos;
            }
            
            // 跳过数据
            if (hdr.op == WalOp.PUT) {
                f.seek(hdr.keyLen + hdr.valLen, 1); // 相对当前位置
            } else if (hdr.op == WalOp.REMOVE) {
                f.seek(hdr.keyLen, 1);
            }
        }
        
        // 从最后一个检查点开始重放
        f.seek(lastCheckpoint >= 0 ? lastCheckpoint + WalHeader.sizeof : 0);
        
        while (true) {
            WalHeader hdr;
            auto read = f.rawRead((cast(ubyte*)&hdr)[0 .. WalHeader.sizeof]);
            if (read.length != WalHeader.sizeof) break;
            
            if (hdr.op == WalOp.CHECKPOINT) continue;
            
            // 读取键
            ubyte[] keyBuf;
            if (hdr.keyLen > 0) {
                keyBuf = new ubyte[hdr.keyLen];
                read = f.rawRead(keyBuf);
                if (read.length != hdr.keyLen) break;
            }
            
            // 读取值（仅 PUT）
            ubyte[] valBuf;
            if (hdr.op == WalOp.PUT && hdr.valLen > 0) {
                valBuf = new ubyte[hdr.valLen];
                read = f.rawRead(valBuf);
                if (read.length != hdr.valLen) break;
            }
            
            // 验证校验和
            if (hdr.op == WalOp.PUT) {
                uint keyCrc = checksum(keyBuf.ptr, hdr.keyLen);
                uint valCrc = checksum(valBuf.ptr, hdr.valLen);
                if ((keyCrc ^ valCrc) != hdr.checksum) continue; // 校验失败，跳过
                onPut(keyBuf.ptr, hdr.keyLen, valBuf.ptr, hdr.valLen);
            } else if (hdr.op == WalOp.REMOVE) {
                uint keyCrc = checksum(keyBuf.ptr, hdr.keyLen);
                if (keyCrc != hdr.checksum) continue; // 校验失败，跳过
                onRemove(keyBuf.ptr, hdr.keyLen);
            }
        }
        
        return true;
    }
    
    /**
     * 清理 WAL 日志
     */
    void clear() {
        close();
        if (.exists(walPath_)) {
            remove(walPath_);
        }
    }
    
    /**
     * 创建检查点（合并 WAL 到数据文件后调用）
     */
    bool checkpoint() {
        if (!logCheckpoint()) return false;
        close();
        
        version (Windows) {
            import core.sys.windows.windows : MoveFileExW, MOVEFILE_REPLACE_EXISTING;
            import std.conv : to;
            
            if (.exists(walPath_)) {
                auto wSrc = walPath_.to!wstring();
                string oldPath = walPath_ ~ ".old";
                auto wDst = oldPath.to!wstring();
                MoveFileExW(wSrc.ptr, wDst.ptr, MOVEFILE_REPLACE_EXISTING);
            }
        } else {
            if (.exists(walPath_)) {
                string oldPath = walPath_ ~ ".old";
                if (.exists(oldPath)) remove(oldPath);
                rename(walPath_, oldPath);
            }
        }
        
        return open();
    }
}
