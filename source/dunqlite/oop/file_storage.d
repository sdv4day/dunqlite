/**
 * 文件存储实现
 * 
 * 基于文件系统的键值存储，支持持久化
 * 使用 WAL (Write-Ahead Logging) 提供崩溃恢复保护
 */
module dunqlite.oop.file_storage;

import dunqlite.oop.error;
import dunqlite.oop.allocator;
import dunqlite.oop.types;
import dunqlite.oop.cursor;
import dunqlite.oop.storage;
import dunqlite.oop.memory_storage;
import dunqlite.oop.wal;

import core.sync.mutex;
import std.stdio : File;
import std.conv : text;
import std.file : exists, remove, rename;

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
 * 使用 WAL 提供崩溃恢复保护
 */
class FileStorage : Storage {
    private MemoryStorage memStorage_;
    private Mutex lock_;
    private string filePath_;
    private Wal wal_;
    private string tempPath_;

    version (Windows) {
        import core.sys.windows.windows : MultiByteToWideChar, CP_UTF8;

        static wchar[] toWideString(string s) {
            auto result = new wchar[](s.length + 1);
            int len = MultiByteToWideChar(CP_UTF8, 0,
                s.ptr, cast(int)s.length,
                result.ptr, cast(int)result.length);
            result[len] = 0;
            return result[0 .. len + 1];
        }
    }
    
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
        
        filePath_ = filePath;
        tempPath_ = filePath ~ ".tmp";
        
        wal_ = new Wal(filePath_);
        
        memStorage_ = new MemoryStorage(allocator_);
        
        loadFromFile();
        
        replayWal();
        
        wal_.open();
    }
    
    ~this() {
        wal_.close();
        destroy(lock_);
    }
    
    /**
     * 从文件加载记录
     */
    private void loadFromFile() {
        File f;
        try {
            f = File(filePath_, "rb");
        } catch (Exception e) {
            return;
        }
        
        scope(exit) f.close();
        
        ubyte[HEADER_SIZE] headerBuf;
        auto bytesRead = f.rawRead(headerBuf[]);
        if (bytesRead.length < HEADER_SIZE) {
            return;
        }
        
        FileHeader* header = cast(FileHeader*) headerBuf.ptr;
        if (header.magic != MAGIC) {
            return;
        }
        
        if (header.ver != VERSION) {
            return;
        }
        
        while (true) {
            RecordHeader recHdr;
            bytesRead = f.rawRead((cast(ubyte*)&recHdr)[0 .. RecordHeader.sizeof]);
            if (bytesRead.length != RecordHeader.sizeof) {
                break;
            }
            
            if (recHdr.keyLength == 0) break;
            
            auto keyBuf = new ubyte[recHdr.keyLength];
            auto keyRead = f.rawRead(keyBuf);
            if (keyRead.length != recHdr.keyLength) {
                break;
            }
            
            if (recHdr.valueLength == 0) break;
            auto valBuf = new ubyte[cast(size_t)recHdr.valueLength];
            auto valRead = f.rawRead(valBuf);
            if (valRead.length != cast(size_t)recHdr.valueLength) {
                break;
            }
            
            memStorage_.put(keyRead.ptr, cast(int)recHdr.keyLength, 
                           valRead.ptr, cast(long)recHdr.valueLength);
        }
    }
    
    /**
     * 重放 WAL 日志（崩溃恢复）
     */
    private void replayWal() {
        if (!wal_.exists()) return;
        
        wal_.replay(
            (const(void)* key, uint keyLen, const(void)* value, uint valLen) {
                int rc = memStorage_.put(key, cast(int)keyLen, value, cast(long)valLen);
                return rc == ErrorCode.OK;
            },
            (const(void)* key, uint keyLen) {
                int rc = memStorage_.remove(key, cast(int)keyLen);
                return rc == ErrorCode.OK;
            }
        );
    }
    
    /**
     * 保存记录到文件（原子写入）
     */
    private int saveToFile() {
        int writeResult = writeTempFile();
        if (writeResult != ErrorCode.OK) {
            return writeResult;
        }
        
        return atomicRename();
    }
    
    /**
     * 写入临时文件
     */
    private int writeTempFile() {
        File f;
        try {
            f = File(tempPath_, "wb");
        } catch (Exception e) {
            return ErrorCode.IO_ERROR;
        }
        
        scope(exit) {
            f.flush();
            f.close();
        }
        
        FileHeader header;
        header.recordCount = memStorage_.count();
        f.rawWrite((cast(ubyte*)&header)[0 .. FileHeader.sizeof]);
        
        auto cursor = memStorage_.createCursor();
        scope(exit) {
            cursor.reset();
            destroy(cursor);
        }
        
        for (cursor.moveFirst(); cursor.isValid(); cursor.moveNext()) {
            RecordHeader recHdr;
            recHdr.keyLength = cursor.keyLength();
            recHdr.valueLength = cursor.valueLength();
            f.rawWrite((cast(ubyte*)&recHdr)[0 .. RecordHeader.sizeof]);
            
            f.rawWrite((cast(ubyte*)cursor.key())[0 .. recHdr.keyLength]);
            f.rawWrite((cast(ubyte*)cursor.value())[0 .. recHdr.valueLength]);
        }
        
        return ErrorCode.OK;
    }
    
    /**
     * 原子重命名临时文件
     */
    private int atomicRename() {
        version (Windows) {
            import core.sys.windows.windows : MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH;
            
            auto wSrc = toWideString(tempPath_);
            auto wDst = toWideString(filePath_);
            if (!MoveFileExW(wSrc.ptr, wDst.ptr, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
                return ErrorCode.IO_ERROR;
            }
        } else {
            try {
                if (exists(filePath_)) {
                    .remove(filePath_);
                }
                .rename(tempPath_, filePath_);
            } catch (Exception e) {
                return ErrorCode.IO_ERROR;
            }
        }
        
        return ErrorCode.OK;
    }
    
    override int put(const(void)* key, int keyLen, const(void)* value, long valueLen) {
        lock_.lock();
        scope(exit) lock_.unlock();
        
        if (!wal_.logPut(key, cast(uint)keyLen, value, cast(uint)valueLen)) {
            return ErrorCode.IO_ERROR;
        }
        
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
        
        if (!wal_.logRemove(key, cast(uint)keyLen)) {
            return ErrorCode.IO_ERROR;
        }
        
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
        
        int rc = saveToFile();
        if (rc == ErrorCode.OK) {
            wal_.checkpoint();
        }
        return rc;
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
            wal_.checkpoint();
            memStorage_.clear();
        }
        return rc;
    }
}

unittest {
    import std.stdio;
    import std.file : exists, remove;

    static void cleanupTestFiles(string basePath) {
        foreach (suffix; ["", ".lock", ".wal", ".wal.old"]) {
            auto p = basePath ~ suffix;
            if (exists(p)) {
                try { remove(p); } catch (Exception) {}
            }
        }
    }

    writeln("[unittest] FileStorage 创建/写入/读取/关闭");
    {
        string testPath = "test_file_storage_db.tmp";
        cleanupTestFiles(testPath);

        auto fs = new FileStorage(testPath);
        scope(exit) {
            destroy(fs);
            cleanupTestFiles(testPath);
        }

        fs.put("key1".ptr, 4, "val1".ptr, 4);
        fs.put("key2".ptr, 4, "val2".ptr, 4);
        assert(fs.count() == 2);

        long bufLen = 256;
        char[256] buf;
        int rc = fs.get("key1".ptr, 4, buf.ptr, &bufLen);
        assert(rc == ErrorCode.OK);
        assert(bufLen == 4);

        assert(fs.contains("key1".ptr, 4));
        assert(!fs.contains("missing".ptr, 7));

        fs.remove("key1".ptr, 4);
        assert(fs.count() == 1);
    }

    writeln("[unittest] FileStorage sync 刷盘");
    {
        string testPath = "test_sync_db.tmp";
        cleanupTestFiles(testPath);

        auto fs = new FileStorage(testPath);
        scope(exit) {
            destroy(fs);
            cleanupTestFiles(testPath);
        }

        fs.put("k1".ptr, 2, "v1".ptr, 2);
        int rc = fs.sync();
        assert(rc == ErrorCode.OK);
    }

    writeln("[unittest] FileStorage 持久化与重新加载");
    {
        string testPath = "test_persist_db.tmp";
        cleanupTestFiles(testPath);

        auto fs1 = new FileStorage(testPath);
        fs1.put("name".ptr, 4, "DunQLite".ptr, 8);
        fs1.put("ver".ptr, 3, "2.0".ptr, 3);
        fs1.sync();
        destroy(fs1);

        auto fs2 = new FileStorage(testPath);
        scope(exit) {
            destroy(fs2);
            cleanupTestFiles(testPath);
        }

        assert(fs2.count() == 2);
        assert(fs2.contains("name".ptr, 4));

        long bufLen = 256;
        char[256] buf;
        int rc = fs2.get("name".ptr, 4, buf.ptr, &bufLen);
        assert(rc == ErrorCode.OK);
        assert(bufLen == 8);
    }

    writeln("[unittest] FileStorage clear");
    {
        string testPath = "test_clear_db.tmp";
        cleanupTestFiles(testPath);

        auto fs = new FileStorage(testPath);
        scope(exit) {
            destroy(fs);
            cleanupTestFiles(testPath);
        }

        fs.put("k1".ptr, 2, "v1".ptr, 2);
        fs.put("k2".ptr, 2, "v2".ptr, 2);
        assert(fs.count() == 2);

        fs.clear();
        assert(fs.count() == 0);
        assert(fs.isEmpty());
    }

    writeln("[unittest] FileStorage createCursor");
    {
        string testPath = "test_cursor_db.tmp";
        cleanupTestFiles(testPath);

        auto fs = new FileStorage(testPath);
        scope(exit) {
            destroy(fs);
            cleanupTestFiles(testPath);
        }

        fs.put("k1".ptr, 2, "v1".ptr, 2);
        fs.put("k2".ptr, 2, "v2".ptr, 2);

        auto cursor = fs.createCursor();
        assert(cursor !is null);

        int count = 0;
        for (cursor.moveFirst(); cursor.isValid(); cursor.moveNext()) {
            count++;
        }
        assert(count == 2);

        cursor.reset();
        destroy(cursor);
    }
}
