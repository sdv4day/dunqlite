/**
 * 文件存储实现
 * 
 * 基于文件系统的键值存储，支持持久化
 */
module dunqlite.oop.file_storage;

import dunqlite.oop.error;
import dunqlite.oop.allocator;
import dunqlite.oop.types;
import dunqlite.oop.cursor;
import dunqlite.oop.storage;
import dunqlite.oop.memory_storage;

import core.sync.mutex;
import std.stdio : File;
import std.conv : text;

/**
 * 文件格式定义
 */
enum {
    MAGIC_LEN = 8,
    VERSION = 1,
    HEADER_SIZE = 32,
}

enum string MAGIC = "DUNQLITE";

/**
 * 文件头结构
 */
struct FileHeader {
    char[MAGIC_LEN] magic = MAGIC;
    uint ver = VERSION;
    uint recordCount;
    ubyte[16] reserved;
}

/**
 * 记录头结构
 */
struct RecordHeader {
    uint keyLength;
    ulong valueLength;
}

/**
 * FileStorage - 文件存储
 * 
 * 启动时从文件加载记录到内存哈希表，关闭时写回文件
 */
class FileStorage : Storage {
    private MemoryStorage memStorage_;
    private Mutex lock_;
    private string filePath_;
    
    /**
     * 构造函数
     * 
     * 参数：
     *   filePath = 数据库文件路径
     *   alloc = 内存分配器
     */
    this(string filePath, Allocator alloc = null) {
        super(alloc);
        lock_ = new Mutex();
        
        // 先初始化 memStorage_，再加锁
        memStorage_ = new MemoryStorage(allocator_);
        
        filePath_ = filePath;
        
        // 从文件加载记录
        loadFromFile();
    }
    
    ~this() {
        // 析构函数不调用close()，避免循环调用
        destroy(lock_);
    }
    
    /**
     * 从文件加载记录
     */
    private void loadFromFile() {
        import std.stdio : writefln;
        
        File f;
        try {
            f = File(filePath_, "rb");
        } catch (Exception e) {
            return; // 文件不存在或打开失败，视为新数据库
        }
        
        scope(exit) f.close();
        
        // 读取文件头
        ubyte[HEADER_SIZE] headerBuf;
        auto bytesRead = f.rawRead(headerBuf[]);
        if (bytesRead.length < HEADER_SIZE) {
            return; // 文件太小，无效
        }
        
        FileHeader* header = cast(FileHeader*) headerBuf.ptr;
        if (header.magic != MAGIC) {
            return; // 魔数不匹配，无效文件
        }
        
        if (header.ver != VERSION) {
            return; // 版本不匹配
        }
        
        writefln("[FileStorage] 从文件加载 %d 条记录", header.recordCount);
        
        // 读取所有记录
        while (true) {
            RecordHeader recHdr;
            bytesRead = f.rawRead((cast(ubyte*)&recHdr)[0 .. RecordHeader.sizeof]);
            if (bytesRead.length != RecordHeader.sizeof) {
                break;
            }
            
            if (recHdr.keyLength == 0) break;
            
            // 读取键
            if (recHdr.keyLength > 1024) {
                writefln("[FileStorage] 键过长: %d", recHdr.keyLength);
                break;
            }
            ubyte[1024] keyTmp = void;
            auto keyRead = f.rawRead(keyTmp[0 .. recHdr.keyLength]);
            if (keyRead.length != recHdr.keyLength) {
                writefln("[FileStorage] 读取键失败: 需要%d, 实际%d", recHdr.keyLength, keyRead.length);
                break;
            }
            
            // 读取值
            if (recHdr.valueLength == 0) break;
            if (recHdr.valueLength > 4096) {
                writefln("[FileStorage] 值过长: %d", recHdr.valueLength);
                break;
            }
            ubyte[4096] valTmp = void;
            auto valRead = f.rawRead(valTmp[0 .. cast(size_t)recHdr.valueLength]);
            if (valRead.length != cast(size_t)recHdr.valueLength) {
                writefln("[FileStorage] 读取值失败: 需要%d, 实际%d", recHdr.valueLength, valRead.length);
                break;
            }
            
            // 插入到内存哈希表（MemoryStorage.put 内部会复制数据）
            int rc = memStorage_.put(keyRead.ptr, cast(int)recHdr.keyLength, 
                           valRead.ptr, cast(long)recHdr.valueLength);
            if (rc != ErrorCode.OK) {
                writefln("[FileStorage] 插入记录失败: rc=%d", rc);
            }
        }
    }
    
    /**
     * 保存记录到文件
     */
    private int saveToFile() {
        import std.stdio : writefln;
        
        File f;
        try {
            f = File(filePath_, "wb");
        } catch (Exception e) {
            writefln("[FileStorage] 创建文件失败: %s", e.msg);
            return ErrorCode.IO_ERROR;
        }
        
        scope(exit) {
            f.flush();
            f.close();
        }
        
        writefln("[FileStorage] 开始写入 %d 条记录", memStorage_.count());
        
        // 写入文件头
        FileHeader header;
        header.recordCount = memStorage_.count();
        f.rawWrite((cast(ubyte*)&header)[0 .. FileHeader.sizeof]);
        
        // 遍历所有记录写入文件
        auto cursor = memStorage_.createCursor();
        scope(exit) {
            cursor.reset();
            destroy(cursor);
        }
        
        int written = 0;
        for (cursor.moveFirst(); cursor.isValid(); cursor.moveNext()) {
            RecordHeader recHdr;
            recHdr.keyLength = cursor.keyLength();
            recHdr.valueLength = cursor.valueLength();
            f.rawWrite((cast(ubyte*)&recHdr)[0 .. RecordHeader.sizeof]);
            
            f.rawWrite((cast(ubyte*)cursor.key())[0 .. recHdr.keyLength]);
            f.rawWrite((cast(ubyte*)cursor.value())[0 .. recHdr.valueLength]);
            written++;
        }
        
        writefln("[FileStorage] 写入 %d 条记录完成", written);
        
        return ErrorCode.OK;
    }
    
    override int put(const(void)* key, int keyLen, const(void)* value, long valueLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.put(key, keyLen, value, valueLen);
    }
    
    override int get(const(void)* key, int keyLen, void* buf, long* bufLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.get(key, keyLen, buf, bufLen);
    }
    
    override int remove(const(void)* key, int keyLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.remove(key, keyLen);
    }
    
    override bool contains(const(void)* key, int keyLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.contains(key, keyLen);
    }
    
    override Cursor createCursor() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.createCursor();
    }
    
    override void clear() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        memStorage_.clear();
    }
    
    override uint count() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return memStorage_.count();
    }
    
    /**
     * 刷盘保存
     * 
     * 返回：
     *   错误码
     */
    int sync() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        return saveToFile();
    }
    
    /**
     * 关闭存储并保存
     * 
     * 返回：
     *   错误码
     */
    int close() {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        int rc = saveToFile();
        if (rc == ErrorCode.OK) {
            memStorage_.clear();
        }
        return rc;
    }
}
